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
import renderers;
import webinterface;
import messages;

import core.time;
import prefs;

Strip createStrip(uint nrOfLeds, immutable(Prefs) settings) {
    if (settings.get("tcpstrip") != "") {
        auto host = settings.get("tcpstrip");
        info("tcpstrip: ", host);
        return new TcpStrip(nrOfLeds, host);
    }
    info("spistrip");
    return new SpiStrip(nrOfLeds);
}

void renderLoop(uint nrOfLeds, immutable(Prefs) settings)
{
    try
    {
        import dotstar;
        auto strip = createStrip(nrOfLeds, settings);
        bool finished = false;
        Tid generator;
        bool hasGenerator = false;
        while (!finished)
        {
            import std.stdio;

            const fps = 20;
            const msPerFrame = (1000 / fps).msecs;
            std.datetime.stopwatch.StopWatch sw;
            sw.reset();
            sw.start();
            if (hasGenerator)
            {
                generator.send(thisTid, Render());
            }
            // dfmt off
            receive(
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
                (SetGenerator setGenerator, Tid tid)
                {
                    info("new generator");
                    generator = tid;
                    hasGenerator = true;
                },
                (Tid sender, Shutdown s) {
                    info("rendere received shutdown");
                    finished = true;
                },
                (OwnerTerminated t) {
                    info("renderer owner terminated");
                    finished = true;
                });
            // dfmt on
        }
    }
    catch (Exception e)
    {
        error(e);
    }

}

int main(string[] args)
{
    import vibe.http.router;
    import vibe.http.server;
    import vibe.core.core : runApplication;
    import vibe.web.web;
    import std.process;
    if (args.length >= 2)
    {
        switch (args[1])
        {
        case "miditest":
            {

                import miditest;

                return miditest.miditest(args.remove(1));
            }
        case "tcpreceiver":
            {
                import tcpreceiver;

                return tcpreceiver.receive(args.remove(1));
            }
        default:
            error("unknown argument ", args[1]);
            return 1;
        }
    }

    import prefs;
    auto settings = prefs.load("settings.yaml", "settings.yaml.%s".format(execute("hostname").output.strip));
    auto nrOfLeds = settings.get("nr_of_leds").to!uint;
    Tid renderer = spawnLinked(&renderLoop, nrOfLeds, settings);
    // dfmt off
    auto profiles = new Profiles(renderer,
        [
            new Sin("sin", nrOfLeds, Color(255, 0, 0), 2f, 1f),
            new Sum("sum", nrOfLeds,
                    [
                        new Sin("sin1", nrOfLeds, Color(255, 0, 0), 2f, 0.3f),
                        new Sin("sin2", nrOfLeds, Color(0, 255, 0), 3, -0.3f)
                     ]),
            new Midi("midi", nrOfLeds, settings),
         ]);
    // dfmt on
    auto router = new URLRouter();
    router.registerWebInterface(new WebInterface(profiles));

    auto httpSettings = new HTTPServerSettings;
    httpSettings.port = 4567;
    auto listener = listenHTTP(httpSettings, router);

    runApplication();

    profiles.shutdown();
    return 0;
}
