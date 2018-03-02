import std.stdio;

import std.concurrency;
import prefs;
import state;
import messages;

auto getState(T)(T prefs) {
    if (prefs.get("mode", "") == "test") {
        return State("something", [
                                   Profile("profile1", [
                                                        Parameter("p1", "color", ["value":"#00ff00"]),
                                                        Parameter("p2", "color", ["value":"#ff0000"]),
                                                        Parameter("p3", "float", ["value":"1.0", "min":"0.0", "max":"10.0"])
                                                        ]),
                                   Profile("profile2")]);
    } else {
        return State("rainbow1", [Profile("rainbow1"), Profile("rainbow2")]);
    }
}

auto routes(immutable(Prefs) prefs, Tid renderer) {
    import vibe.http.router;
    /*
    import vibe.web.web;
    */
    import vibe.web.rest;
    import restinterface;

    import vibe.http.fileserver;

    // dfmt off
    return new URLRouter()
        //.registerWebInterface(new WebInterface(renderer))
        .registerRestInterface(new RestInterface(renderer))
        .get("*", serveStaticFiles("./public/"));
    // dfmt on
}

auto httpSettings(T)(T prefs) {
    import vibe.http.server;
    import std.conv;
    auto httpSettings = new HTTPServerSettings;
    httpSettings.port = prefs.get("port").to!ushort;
    return httpSettings;
}

int main(string[] args)
{
    import std.process;
    import std.string;
    import std.experimental.logger;
    info("sdrip3");

    auto s = prefs.load("settings.yaml",
                        "settings.yaml.%s".format(execute("hostname").output.strip));
    if (args.length > 1 && args[1] == "test") {
        import std.algorithm;
        s.add("mode", "test");
    }
    writeln(args);
    writeln(s);

    auto settings = cast(immutable)s;

    auto state = getState(settings);

    import rendering;
    auto renderer = std.concurrency.spawnLinked(&renderloop, settings);

    import mdns;
    auto announcement = mdns.announceServer(settings);

    import vibe.http.server : listenHTTP;
    auto listener = listenHTTP(httpSettings(settings), routes(settings, renderer));

    import vibe.core.core : runApplication;
    auto unrecognized = (string[] unrecognizedArgs) {
        writeln(args, unrecognizedArgs);
    };
    auto status = runApplication(unrecognized);

    renderer.shutdownChild();

    import core.thread;
    auto threads = Thread.getAll();
    foreach (t; threads) {
        writeln(t.name, t.isRunning);
    }

    announcement.kill();
    announcement.wait();
    writeln("shutting down complete");

    return 0;
}
