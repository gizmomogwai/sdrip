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

auto setupMqtt(immutable(Prefs) prefs, Tid renderer)
{
    import mqttd;
    import vibe.data.json;
    import core.time;

    auto topic = prefs.get("mqtt.topic");
    if (topic == "")
    {
        return oc(no!MqttClient);
    }

    auto user = prefs.get("mqtt.user");
    if (user == "")
    {
        return oc(no!MqttClient);
    }

    auto mqttSettings = Settings();
    mqttSettings.clientId = "sdrip";
    mqttSettings.reconnect = 10.seconds;
    mqttSettings.host = "mqtt.beebotte.com";
    mqttSettings.userName = user;
    mqttSettings.keepAlive = 10;
    mqttSettings.onPublish = (scope MqttClient client, in Publish packet) {
        info(packet.topic);
        if (packet.topic == topic)
        {
            auto json = parseJsonString((cast(const char[]) packet.payload).idup);
            auto command = json["data"].get!string.toLower;
            info(packet.topic, ": ", json);
            if (!command.find("toggle").empty
                    || !command.find("on").empty || !command.find("off").empty)
            {
                renderer.sendReceive!Toggle;
            }
            else if (!command.find("activate").empty)
            {
                auto parts = command.split(" ");
                {
                    renderer.sendReceive!Activate(parts.retro.front);
                }
            }
        }
    };
    mqttSettings.onConnAck = (scope MqttClient client, in ConnAck packet) {
        if (packet.returnCode != ConnectReturnCode.ConnectionAccepted)
            return;
        client.subscribe([topic], QoSLevel.QoS2);
    };
    mqttSettings.onDisconnect = (scope MqttClient client) {
        writeln("Got disconnected");
    };

    auto mqtt = new MqttClient(mqttSettings);
    mqtt.connect();
    return oc(some(mqtt));
}

int main(string[] args)
{
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

    auto mqtt = setupMqtt(settings, renderer);
    scope (exit)
    {
        mqtt.disconnect();
    }

    auto status = runApplication(null);

    return 0;
}
