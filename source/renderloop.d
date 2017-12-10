/// renderloop
module renderloop;

import prefs;
import timer;
import core.thread;
import stripfactory;
import std.concurrency;
import std.experimental.logger;
import std.string;
import messages;
import sdrip;
import renderer;
import renderer.sin;
import renderer.sum;
import renderer.midi;
import renderer.rainbow;

void renderLoop(uint nrOfLeds, immutable(Prefs) settings, shared(Timer) timer)
{
    scope (exit)
    {
        info("renderLoop finished");
    }
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
            new Rainbow("rainbow", nrOfLeds, 1)
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
        while (!finished)
        {
            import std.stdio;

            // dfmt off
            receive(
                    (Tid sender, Status status)
                    {
                        import core.time;
                        info("status");
                        sender.send(Status.Result("idle: %sms, rendering: %sms, percent: %.2f%%"
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
}

@("Formatting floats") unittest
{
    import unit_threaded;
    import std.string;

    "%.1f".format(1.0f).shouldEqual("1.0");
    "%.2f".format(10.0f).shouldEqual("10.00");
}
