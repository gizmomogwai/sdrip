/// main module, renderloop, strip initialization
module app;

import std.stdio;
import std.string;
import std.experimental.logger;
import dyaml;
import std.conv;
import std.datetime.stopwatch;
import core.thread;
import dotstar;
import std.array;
import std.concurrency;
import std.algorithm;
import std.range;
import sdrip;
import webinterface;
import messages;
import renderer;
import renderer.sin;
import renderer.sum;
import renderer.midi;

import core.time;
import prefs;

Strip createStrip(uint nrOfLeds, immutable(Prefs) settings)
{
    if (settings.get("dummystrip") != "")
    {
        return new DummyStrip(nrOfLeds);
    }
    if (settings.get("tcpstrip") != "")
    {
        auto host = settings.get("tcpstrip");
        info("tcpstrip: ", host);
        return new TcpStrip(nrOfLeds, host);
    }
    info("spistrip");
    return new SpiStrip(nrOfLeds);
}

void renderLoop(uint nrOfLeds, immutable(Prefs) settings, shared(Timer) timer)
{
    Thread.getThis.name = "renderLoop";
    Thread.getThis.isDaemon = false;

    // dfmt off
    auto profiles = new Profiles(thisTid,
        [
            new Sin("sin", nrOfLeds, Color(0xff, 0x80, 0), 2f, 1f),
            new Sum("sum", nrOfLeds,
                [
                   new Sin("sin1", nrOfLeds, Color(255, 0, 0), 2f, 3f),
                   new Sin("sin2", nrOfLeds, Color(0, 255, 0), 3, -3f)
                ]),
            new Midi("midi", nrOfLeds, settings),
         ]);
    // dfmt on

    try
    {
        import dotstar;

        auto strip = createStrip(nrOfLeds, settings);
        scope (exit)
        {
            strip.close();
        }
        bool finished = false;
        Tid renderer;
        string rendererName;
        bool hasRenderer = false;
        const fps = 20;
        const msPerFrame = (1000 / fps).msecs;
        std.datetime.stopwatch.StopWatch sw;
        Duration idleTime;
        Duration renderTime;
        sw.reset();
        sw.start();
        while (!finished)
        {
            import std.stdio;

            // dfmt off
            receive(
                    (Tid sender, Status status)
                    {
                        import core.time;
                        info("status");
                        sender.send(Status.Result("idle: %sms, rendering: %sms, percent: %.1g"
                                                  .format(idleTime.total!"msecs",
                                                          renderTime.total!"msecs",
                                                          100 * (double(renderTime.total!"msecs") / (double(renderTime.total!"msecs") + double(idleTime.total!"msecs"))))));
                   },
                (Tid sender, Index index)
                {
                    info("index");
                    sender.send(Index.Result(Index.Result.Data(rendererName,profiles.renderers.map!(p => p.name).array)));
                },
                (Render render)
                {
                    sw.reset();
                    sw.start();
                    if (hasRenderer) {
                        renderer.send(thisTid, Render());
                    }
                },
                (Render.Result result)
                {
                    try {
                        foreach (idx, p; result.data) {
                            strip.set(cast(uint)idx, p);
                        }
                        strip.refresh();
                        auto duration = sw.peek();
                        renderTime += duration;
                        if (duration < msPerFrame) {
                            auto delay = msPerFrame - duration;
                            idleTime += delay;
                            auto tid = thisTid;
                            timer.runIn(() => tid.send(Render()), delay);
                        } else {
                            thisTid.send(Render());
                        }
                    } catch (Throwable t) {
                        error("error ", t);
                    }
                },
                (SetRenderer setRenderer, Tid tid, string name)
                {
                    info("new renderer");
                    renderer = tid;
                    rendererName = name;
                    hasRenderer = true;
                    idleTime = Duration.zero;
                    renderTime = Duration.zero;
                    thisTid.send(Render());
                },
                (Tid sender, Activate request) {
                    profiles.activate(request.name);
                    sender.send(request.Result(true));
                },
                (Tid sender, GetCurrent request) {
                    sender.send(request.Result(rendererName));
                },
                (Tid sender, GetProperties request) {
                    renderer.send(sender, request);
                },
                (Tid sender, Shutdown s) {
                    info("received shutdown");
                    finished = true;
                    sender.send(s.Result());
                },
                (Tid sender, Apply apply)
                {
                    renderer.send(sender, apply);
                },
                (OwnerTerminated t) {
                    info("renderer owner terminated");
                    finished = true;
                },
                (LinkTerminated lt) {
                    info("link terminated ", lt);
                    //                    finished = true;
                },
                (Variant v) {
                    error("unknown message received: ", v);
                }
            );
            // dfmt on
        }
    }
    catch (Exception e)
    {
        error("finished with ", e);
        error(e);
    }
    writeln("Renderer.finished");
}

alias Runnable = void delegate();

class BlockingQueue(T)
{
    import core.sync.condition;
    import core.sync.mutex;
    import std.container;

    private Mutex mutex;
    private Condition condition;
    private DList!T items;

    this()
    {
        mutex = new Mutex();
        condition = new Condition(mutex);
    }

    void add(T item) shared
    {
        synchronized (mutex)
        {
            (cast() items).insertBack(item);
            (cast() condition).notifyAll();
        }
    }

    T remove() shared
    {
        synchronized (mutex)
        {
            while ((cast() items).empty())
            {
                (cast() condition).wait();
            }

            while (!(cast() items).front.due)
            {
                auto remaining = (cast() items).front.remainingDuration;
                (cast() condition).wait(remaining);
            }

            T res = (cast() items).front;
            (cast() items).removeFront;
            return res;
        }
    }
}

struct Task
{
    import std.datetime;

    Runnable run;
    SysTime at;
    bool due()
    {
        return at <= Clock.currTime;
    }

    Duration remainingDuration()
    {
        return at - Clock.currTime;
    }
}

class Timer : Thread
{
    import std.datetime;

    string name;
    shared(BlockingQueue!Task) tasks;
    this(string name)
    {
        this.name = "Timer(%s)".format(name);
        tasks = new shared(BlockingQueue!Task);
        super(&run);
    }

    void runIn(Runnable run, Duration delta) shared
    {
        runAt(run, Clock.currTime() + delta);
    }

    void runAt(Runnable run, SysTime at) shared
    {
        tasks.add(Task(run, at));
    }

    private void run()
    {
        scope (exit)
        {
            writeln("%s finished".format(name));
        }
        Thread.getThis.name = name;

        while (true)
        {
            tasks.remove.run();
        }
    }
}

int main(string[] args)
{

    import misc.miditest;
    import misc.midisim;
    import misc.tcpreceiver;

    import std.process;
    import vibe.core.core : runApplication, exitEventLoop;
    import vibe.http.fileserver;
    import vibe.http.router;
    import vibe.http.server;
    import vibe.web.web;

    if (args.length >= 2)
    {
        switch (args[1])
        {
        case "miditest":
            return misc.miditest.miditest(args.remove(1));
        case "tcpreceiver":
            return misc.tcpreceiver.receive(args.remove(1));
        case "midisim":
            return misc.midisim.midisim(args.remove(1));
        default:
            error("unknown argument ", args[1]);
            return 1;
        }
    }

    import prefs;

    auto settings = prefs.load("settings.yaml",
            "settings.yaml.%s".format(execute("hostname").output.strip));
    auto nrOfLeds = settings.get("nr_of_leds").to!uint;

    auto timer = cast(shared) new Timer("main");
    (cast() timer).start;

    Tid renderer = std.concurrency.spawnLinked(&renderLoop, nrOfLeds, settings, timer);
    auto router = new URLRouter().registerWebInterface(new WebInterface(renderer))
        .get("*", serveStaticFiles("./public/"));

    auto httpSettings = new HTTPServerSettings;
    httpSettings.port = 4567;
    auto listener = listenHTTP(httpSettings, router);

    auto status = runApplication();
    writeln("vibe finished");

    std.concurrency.send(renderer, std.concurrency.thisTid, Shutdown());
    bool rendererRunning = true;
    while (rendererRunning)
    {
        try
        {
            std.concurrency.receive((LinkTerminated r) {
                info("link terminated");
                rendererRunning = false;
            }, (Shutdown.Result r) {
                info("renderer sent back result");
                rendererRunning = false;
            }, (Variant v) { info("received ", v); });
        }
        catch (Exception e)
        {
            info(e);
        }
    }

    foreach (t; Thread.getAll)
    {
        writeln("thread '%s': running = %s, daemon = %s".format(t.name, t.isRunning, t.isDaemon));
    }

    return 0;
}

shared static this()
{
    writeln("static constructor");
}

shared static ~this()
{
    writeln("module destructor");
}
