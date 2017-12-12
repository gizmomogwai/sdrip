/// main module, renderloop, strip initialization
module app;

import std.stdio;
import std.string;
import std.experimental.logger;
import dyaml;
import std.conv;
import dotstar;
import std.concurrency;
import std.algorithm;
import sdrip;
import webinterface;
import messages;
import timer;
import renderloop;
import stripfactory;

import prefs;

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

    info("shutting down the rest");
    renderer.shutdownAndWait();
    info("shutting down complete");

    return 0;
}
