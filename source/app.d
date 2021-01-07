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
    import std.algorithm;
    import vibe.data.json;

    auto topic = prefs.get("topic");
    if (topic == "")
    {
        return oc(no!MqttClient);
    }

    auto mqttSettings = Settings();
    mqttSettings.clientId = "sdrip";
    mqttSettings.reconnect = 1.sec;
    mqttSettings.host = "mqtt.beebotte.com";
    mqttSettings.userName = "token:token_2M68jYuF3by46hgB";
    mqttSettings.onPublish = (scope MqttClient client, in Publish packet) {
        if (packet.topic == topic)
        {
            auto json = parseJsonString((cast(const char[]) packet.payload).idup);
            auto command = json["data"].get!string;
            info(packet.topic, ": ", json);
            if (command.startsWith("piano toggle")
                    || command.startsWith("piano on") || command.startsWith("piano off"))
            {
                renderer.sendReceive!Toggle;
            }
            else if (command.startsWith("piano activate"))
            {
                auto parts = command.split(" ");
                if (parts.length == 4)
                {
                    renderer.sendReceive!Activate(parts[3]);
                }
            }
        }
    };
    mqttSettings.onConnAck = (scope MqttClient client, in ConnAck packet) {
        if (packet.returnCode != ConnectReturnCode.ConnectionAccepted)
            return;
        client.subscribe([topic], QoSLevel.QoS2);
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
