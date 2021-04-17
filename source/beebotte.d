module beebotte;

import core.time;
import messages;
import mqttd;
import prefs;
import std.experimental.logger;
import std;
import vibe.data.json;

void setup(immutable(Prefs) prefs, Tid renderer)
{
    log("setup mqtt");
    auto topic = prefs.get("mqtt.topic");
    if (topic == "")
    {
        return;
    }

    auto user = prefs.get("mqtt.user");
    if (user == "")
    {
        return;
    }

    string currentProfile;

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
                    currentProfile = parts.retro.front;
                    renderer.sendReceive!Activate(currentProfile);
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

    renderer.send(thisTid, Register());
    bool finished = false;
    try {
    while (!finished) {
        receive(
            (Tid sender, RendererChanged rendererChanged) {
                // adjust beebotte to local value
                if (rendererChanged.name != currentProfile) {
                    currentProfile = rendererChanged.name;
                    // beebotte message format see: https://beebotte.com/docs/mqtt#considerations
                    auto msg = "{\"data\":\"activate %s\", \"write\":true}".format(rendererChanged.name);
                    mqtt.publish(topic, msg, QoSLevel.QoS0, true);
                }
            },
            (OwnerTerminated ot) {
                finished = true;
            }
        );
    }
    } catch (Exception e) {
        error(e);
    }
}

auto setupBeebotte(immutable(Prefs) prefs, Tid renderer)
{
    spawnLinked(&setup, prefs, renderer);
}
