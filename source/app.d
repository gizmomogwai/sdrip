import std.stdio;

import std.concurrency;
import prefs;
import messages;

auto routes(immutable(Prefs) prefs, Tid renderer)
{
    import vibe.http.router;

    import webinterface;
    import vibe.web.web;

    import restinterface;
    import vibe.web.rest;

    import vibe.http.fileserver;

    // dfmt off
    return new URLRouter()
        .registerWebInterface(new WebInterface(renderer))
        .registerRestInterface(new RestInterface(renderer), "api")
        .get("*", serveStaticFiles("./public/"));
    // dfmt on
}

auto httpSettings(T)(T prefs)
{
    import vibe.http.server;
    import std.conv;

    auto bind = prefs.get("bind").to!string;
    return new HTTPServerSettings(bind);
}

int main(string[] args)
{
    import std.process;
    import std.string;
    import std.experimental.logger;
    import std.algorithm;

    info("sdrip");

    if (args.length >= 2)
    {
        import sdrip.misc.tcpreceiver;

        switch (args[1])
        {
        case "tcpreceiver":
            return sdrip.misc.tcpreceiver.receive(args.remove(1));
        default:
            break;
        }
    }
    auto s = prefs.load("settings.yaml",
            "settings.yaml.%s".format(execute("hostname").output.strip));

    auto settings = cast(immutable) s;

    import rendering;

    auto renderer = std.concurrency.spawnLinked(&renderloop, settings);

    import mdns;

    auto announcement = mdns.announceServer(settings);

    import vibe.http.server : listenHTTP;

    auto listener = listenHTTP(httpSettings(settings), routes(settings, renderer));

    import vibe.core.core : runApplication;

    auto status = runApplication(null);

    renderer.shutdownChild();

    import core.thread;

    auto threads = Thread.getAll();
    foreach (t; threads)
    {
        writeln(t.name, t.isRunning);
    }

    announcement.kill();
    announcement.wait();
    writeln("shutting down complete");

    return 0;
}
