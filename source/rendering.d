module rendering;

import core.thread;
import core.time;
import dotstar;
import messages;
import prefs;
import state;
import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.datetime;
import std.experimental.logger;
import std.stdio;
import std.string;
import timer;
import vibe.data.json;
import std.datetime.stopwatch;

auto path(string prefix, string name)
{
    return "%s%s%s".format(prefix, prefix != "" ? "." : "", name);
}

auto getState(immutable(Prefs) prefs)
{
    if (prefs.get("mode", "") == "test")
    {
        return State("something", [Profile("profile1", [Parameter("p1", "color",
                ["value" : "#00ff00"]), Parameter("p2", "color", ["value" : "#ff0000"]),
                Parameter("p3", "float", ["value" : "1.0", "min" : "0.0", "max" : "10.0"])]),
                Profile("profile2")]);
    }
    else
    {
        return State("rainbow1", [Profile("rainbow1"), Profile("rainbow2")]);
    }
}

class Property
{
    abstract Json toJson(string prefix);
    abstract void apply(string key, string value);
}

class WithDefault(T) : Property
{
    string name;
    string type;
    T value;
    T defaultValue;
    this(string name, string type, T value, T defaultValue)
    {
        this.name = name;
        this.type = type;
        this.value = value;
        this.defaultValue = defaultValue;
    }

    override Json toJson(string prefix)
    {
        return Json(["name" : Json(path(prefix, name)), "type" : Json(type),
                "value" : Json(value), "defaultValue" : Json(defaultValue)]);
    }

    override string toString()
    {
        return toJson("").to!string;
    }

    override void apply(string key, string value)
    {
        if (name == key)
        {
            trace(" applying ", key, " -> ", value);
            this.value = value.to!T;
        }
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
class Renderer
{
    string name;
    WithDefault!bool active = withDefault("active", "boolean", true);
    Property[] properties;
    Renderer[] childs;
    this(string name, Property[] properties)
    {
        this.name = name;
        this.properties = properties ~ active;
    }

    Json toJson(string prefix)
    {
        auto path = path(prefix, name);
        auto res = Json([                "name" : Json(path)]);
        if (!properties.empty) {
            res["properties"] = Json(properties.map!(p => p.toJson(path)).array);
        }
        return res;
    }

    abstract Color[] render(uint size);

    void dispatch(string[string[]] pathToValueMap)
    {
        writeln("dispatch on ", name);
        foreach (path, value; pathToValueMap)
        {
            apply(path, value);
        }
    }

    private void apply(const(string)[] path, string value)
    {
        if (!path)
        {
            return;
        }

        if (path[0] == name)
        {
            path = path[1 .. $];
            if (path.length == 1)
            {
                foreach (p; properties)
                {
                    p.apply(path.front, value);
                }
            }
            else if (path.length > 1)
            {
                foreach (c; childs)
                {
                    c.apply(path, value);
                }
            }
        }
    }

    void start()
    {
    }

    void stop()
    {
    }
}

auto renderTo(Renderer renderer, Strip strip)
{
    std.datetime.stopwatch.StopWatch sw;
    auto result = renderer.render(strip.size);
    foreach (idx, p; result)
    {
        strip.set(cast(uint) idx, p);
    }
    strip.refresh();
    return sw.peek;
}

class ColorRenderer : Renderer
{
    WithDefault!string color;
    this(string name, string color)
    {
        this.color = withDefault("color", "color", color);
        super(name, [this.color]);
    }

    override Color[] render(uint size)
    {
        Color[] res;
        res.length = size;
        auto v = (cast(WithDefault!bool) properties[$ - 1]).value;
        if (!v)
        {
            return res;
        }

        auto c = Color(color.value);
        for (int i = 0; i < size; ++i)
        {
            res[i] = c;
        }
        return res;
    }
}

class RainbowRenderer : Renderer
{
    WithDefault!float velocity = withDefault("velocity", "float", 0.2f);
    float phase = 0.0f;
    this(string name)
    {
        writeln(velocity);
        super(name, [velocity]);
    }

    private int hue(float v)
    {
        import std.math;

        while (v >= 360)
        {
            v -= 360;
        }
        while (v < 0)
        {
            v += 360;
        }
        return lround(v).to!int;
    }

    override Color[] render(uint size)
    {
        import std.range;

        phase += velocity.value;
        float s = size.to!float;
        // dfmt off
        return iota(0, size)
            .map!(x => Color.hsv(hue(phase + (x.to!float * 360.0f / s))))
            .array;
        // dfmt on
    }
}

@("colorrenderer") unittest
{
    import std.stdio;

    writeln(new ColorRenderer("red", "#ab0000").toJson("prefix"));
}

class DummyRenderer : Renderer
{
    this()
    {
        super("dummy", []);
    }

    override Color[] render(uint size)
    {
        return null;
    }

    override void start()
    {
    }

    override void stop()
    {
    }
}

struct Render
{
    int id;
    bool isCurrent(int id)
    {
        return this.id == id;
    }
}

void renderloop(immutable(Prefs) settings)
{
    scope (exit)
    {
        info("renderLoop finished");
    }

    try
    {
        auto strip = createStrip(settings);
        const msPerFrame = (1000 / settings.get("fps").to!int).msecs;

        Thread.getThis.name = "renderLoop";
        Thread.getThis.isDaemon = false;
        bool finished = false;

        // dfmt off
        Renderer[] renderers = [
            new ColorRenderer("red", "#ff0000"),
            new ColorRenderer("green", "#00ff00"),
            new ColorRenderer("blue", "#0000ff"),
            new RainbowRenderer("rainbow"),
        ];
        // dfmt on
        Renderer currentRenderer = new DummyRenderer;
        auto timer = new Timer("rendering").start;
        int renderId = 0;
        while (!finished)
        {
            bool rendering = false;
            // dfmt off
            receive(
                (Tid sender, GetState s)
                {
                    auto res = Json(
                        [
                            "current": Json(currentRenderer.name),
                            "renderers": Json(renderers.map!(r => r.toJson("")).array)
                        ]
                    );

                    sender.send(GetState.Result(res));
                },
                (Tid sender, Activate activate)
                {
                    info("rendering.activate");
                    auto newRenderer = renderers.find!(renderer => renderer.name == activate.profile);
                    if (newRenderer.empty)
                    {
                        error("Cannot find %s".format(activate.profile));
                    }
                    else
                    {
                        currentRenderer.stop();
                        currentRenderer = newRenderer.front;
                        currentRenderer.start();
                        renderId++;
                        thisTid.send(Render(renderId));
                    }
                },
                (Tid sender, Set set)
                {
                    info("setting ", set);
                    // transform from string[string] to string[path]
                    string[string[]] pathToValueMap;
                    foreach (key, value; set.data.byKeyValue) {
                        pathToValueMap[key.split(".").array.idup] = value.to!string;
                    }
                    writeln("dispatching ", pathToValueMap);
                    currentRenderer.dispatch(pathToValueMap);
                },
                (Render render)
                {
                    if (!render.isCurrent(renderId))
                    {
                        return;
                    }
                    auto d = currentRenderer.renderTo(strip);
                    scheduleNextRendering(timer, thisTid, d, msPerFrame, render);
                },
                (Tid sender, Shutdown s)
                {
                    finished = true;
                },
                (Variant v) {
                    error("unknown message ", v);
                }
            );
            // dfmt on
        }
        timer.shutdown();
    }
    catch (Exception e)
    {
        error(e);
    }

}

void scheduleNextRendering(Timer timer, Tid tid, Duration lastFrame,
        Duration msPerFrame, Render render)
{
    if (lastFrame < msPerFrame)
    {
        auto delay = msPerFrame - lastFrame;
        timer.runIn(() => tid.send(Render(render.id)), delay);
    }
    else
    {
        tid.send(Render(render.id));
    }
}
