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
import restinterface;
import messages;
import timer;
import renderloop;
import stripfactory;

import prefs;

auto announceServer(immutable(Prefs) settings)
{
    import std.process;

    version (linux)
    {
        auto command = "avahi-publish-service -s %s _dotstar._tcp %s";
    }
    version (OSX)
    {
        auto command = "dns-sd -R %s _dotstar._tcp local %s";
    }
    return spawnShell(command.format(settings.get("location"), settings.get("port")));
}

import vibe.data.json;
import vibe.core.path;
import vibe.web.common;

@path("/")
interface IMyAPI
{
@safe:
    // GET /api/greeting
    @property string greeting();

    // PUT /api/greeting
    @property void greeting(string text);

    // POST /api/users
    @path("/users")
    void addNewUser(string name);

    // GET /api/users
    @property string[] users();

    // GET /api/:id/name
    string getName(int id);

    // GET /some_custom_json
    Json getSomeCustomJson();
}

// vibe.d takes care of all JSON encoding/decoding
// and actual API implementation can work directly
// with native types

class API : IMyAPI
{
    private
    {
        string m_greeting;
        string[] m_users;
    }

    @property string greeting()
    {
        return m_greeting;
    }

    @property void greeting(string text)
    {
        m_greeting = text;
    }

    void addNewUser(string name)
    {
        m_users ~= name;
    }

    @property string[] users()
    {
        return m_users;
    }

    string getName(int id)
    {
        return m_users[id];
    }

    Json getSomeCustomJson()
    {
        Json ret = Json.emptyObject;
        ret["somefield"] = "Hello, World!";
        return ret;
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
    import vibe.web.rest;

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
        .registerRestInterface!Api(new RestInterface(renderer)).registerRestInterface(
                new API()).get("*", serveStaticFiles("./public/"));

    auto httpSettings = new HTTPServerSettings;
    httpSettings.port = 4567;
    auto listener = listenHTTP(httpSettings, router);

    auto announcement = announceServer(settings);

    auto status = runApplication();
    writeln("vibe finished");

    info("shutting down the rest");
    renderer.shutdownAndWait();

    announcement.kill();
    announcement.wait();

    info("shutting down complete");

    return 0;
}
