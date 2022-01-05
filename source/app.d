
import mdns;
import messages;
import prefs;
import rendering;
import std.algorithm;
import std.concurrency;
import std.experimental.logger;
import std.process;
import std.stdio;
import std.string;
import std.range;
import optional;
import beebotte;
import dotstar;

auto routes(immutable(Prefs) prefs, Tid renderer)
{
    import vibe.core.core : exitEventLoop;
    import restinterface;
    import std.functional;
    import vibe.http.fileserver;
    import vibe.http.router;
    import vibe.web.rest;
    import vibe.web.web;
    import webinterface;

    auto webInterface = new WebInterface(renderer);

    // dfmt off
    return new URLRouter()
        .registerWebInterface(webInterface)
        .registerRestInterface(new RestInterface(renderer), "api")
        .get("*", serveStaticFiles("./public/"));
    // dfmt on
}

auto httpSettings(T)(T prefs)
{
    import std.conv;
    import vibe.http.server;

    auto bind = prefs.get("bind").to!string;
    return new HTTPServerSettings(bind);
}

int main(string[] args)
{
/+
    auto strip = new SpiStrip(64);
    for (int i=0; i<64; i++) {
        strip.set(i, cast(ubyte) 0xff, cast(ubyte) i, cast(ubyte) 0, cast(ubyte) 0);
    }
    strip.refresh();
    return 0;
+/

    import core.thread;
    import vibe.core.core : runApplication;
    import vibe.http.server : listenHTTP;

    info("sdrip");
    /+
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
+/
    auto settings = prefs.load("settings.yaml",
            "settings.yaml.%s".format(execute("hostname").output.strip));

    auto renderer = std.concurrency.spawnLinked(&renderloop, settings);

    auto announcement = mdns.announceServer(settings);
    scope (exit)
    {
        announcement.kill;
        announcement.wait;
    }

    auto listener = listenHTTP(httpSettings(settings), routes(settings, renderer));
    scope (exit)
    {
        listener.stopListening;
    }

//    setupBeebotte(settings, renderer); // disable for now

    auto status = runApplication(null);

    return 0;
}
