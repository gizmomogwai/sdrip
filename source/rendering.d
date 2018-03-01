module rendering;

import core.thread;
import messages;
import prefs;
import state;
import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.experimental.logger;
import std.stdio;
import std.string;
import vibe.data.json;


auto path(string prefix, string name) {
    return "%s%s%s".format(prefix, prefix != "" ? "." : "", name);
}
auto getState(immutable(Prefs) prefs) {
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

class Property {
    abstract Json toJson(string prefix);
}

class WithDefault(T) : Property
{
    string name;
    string type;
    T value;
    T defaultValue;
    this(string name, string type, T value, T defaultValue) {
        this.name = name;
        this.type = type;
        this.value = value;
        this.defaultValue = defaultValue;
    }
    override Json toJson(string prefix) {
        return Json(["name": Json(path(prefix, name)),
                     "type": Json(type),
                     "value": Json(value.to!string),
                     "defaultValue": Json(defaultValue.to!string)]);
    }
}

static withDefault(T)(string name, string type, T v)
{
    return new WithDefault!(T)(name, type, v, v);
}

static withDefault(T)(string name, string type, T value, T defaultValue)
{
    return new WithDefault!(T)(name, type, value, defaultValue);
}
/*
class MinMaxWithDefault(T) : WithDefault
{
    T min;
    T max;
    override Json toJson(string prefix) {
    }
}

static minMaxWithDefault(T)(string name, T v, T min, T max)
{
    return new MinMaxWithDefault!(T)(name, v, v, min, max);
}

static minMaxWithDefault(T)(string name, T v, T defaultValue, T min, T max)
{
    return new MinMaxWithDefault!(T)(name, v, defaultValue, min, max);
}
*/
class Renderer {
    string name;
    Property[] properties;
    Renderer[] childs;
    this(string name, Property[] properties) {
        this.name = name;
        this.properties = properties;
    }
    Json toJson(string prefix) {
        auto path = path(prefix, name);
        return Json([
                     "name": Json(path),
                          "properties": Json(properties.map!(p => p.toJson(path)).array)
                          ]);
    }
}


class ColorRenderer : Renderer {
    this(string name, string color) {
        super(name, [
                     withDefault("color", "color", color)
                     ]);
    }
}

@("colorrenderer") unittest {
    import std.stdio;
    writeln(new ColorRenderer("red", "#ab0000").toJson("prefix"));
}


void renderloop(immutable(Prefs) settings)
{
    scope (exit)
    {
        info("renderLoop finished");
    }

    Thread.getThis.name = "renderLoop";
    Thread.getThis.isDaemon = false;
    bool finished = false;

    Renderer[] renderers =
        [
         new ColorRenderer("red", "#ff0000"),
         new ColorRenderer("green", "#00ff00")
                            ];
    while (!finished)
        {

            // dfmt off
            receive(
                    (Tid sender, GetState s) {
                        sender.send(GetState.Result(Json(renderers.map!(r => r.toJson("")).array)));
                    },
                    (Tid sender, Shutdown s) {
                        finished = true;
                    }
                    );
            // dfmt on
        }
}
