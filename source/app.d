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

void renderLoop(uint nrOfLeds, immutable(Prefs) settings)
{
    Thread.getThis.name = "renderLoop";
    Thread.getThis.isDaemon = false;

    // dfmt off
    auto profiles = new Profiles(thisTid,
        [
            new Sin("sin", nrOfLeds, Color(0xff, 0x80, 0), 2f, 1f),
            new Sum("sum", nrOfLeds,
                [
                    new Sin("sin1", nrOfLeds, Color(255, 0, 0), 2f, 0.3f),
                    new Sin("sin2", nrOfLeds, Color(0, 255, 0), 3, -0.3f)
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
        while (!finished)
        {
            import std.stdio;

            const fps = 20;
            const msPerFrame = (1000 / fps).msecs;
            std.datetime.stopwatch.StopWatch sw;
            sw.reset();
            sw.start();
            if (hasRenderer)
            {
                renderer.send(thisTid, Render());
            }
            // dfmt off
            receive(
                (Tid sender, Index index)
                {
                    info("index");
                    sender.send(Index.Result(Index.Result.Data(rendererName,profiles.renderers.map!(p => p.name).array)));
                },
                (Render.Result result)
                {
                    try {
                        foreach (idx, p; result.data) {
                            strip.set(cast(uint)idx, p);
                        }
                        strip.refresh();
                        auto duration = sw.peek();
                        if (duration < msPerFrame) {
                            Thread.sleep(msPerFrame - duration);
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

void anotherOne()
{
    Thread.getThis.name = "another one";
    Thread.getThis.isDaemon = false;
    bool running = true;
    while (running)
    {
        // dfmt off
        receive(
            (OwnerTerminated t)
            {
                info("another got owner terminated");
                running = false;
            },
            (Variant v)
            {
                info("got ", v);
            });
        // dfmt on
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
    Tid renderer = std.concurrency.spawnLinked(&renderLoop, nrOfLeds, settings);
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
