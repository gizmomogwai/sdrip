module rendering;

import core.thread;
import core.time;
import dotstar;
import messages;
import prefs;
import state;
import std;
import std.datetime.stopwatch;
import std.experimental.logger;
import timer;
import vibe.data.json;

auto path(string prefix, string name)
{
    return "%s%s%s".format(prefix, prefix != "" ? "." : "", name);
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
        // dfmt off
        return Json([
                        "name" : Json(path(prefix, name)),
                        "type" : Json(type),
                        "value" : Json(value),
                        "defaultValue" : Json(defaultValue),
                    ]);
        // dfmt on
    }

    override string toString()
    {
        return toJson("").to!string;
    }

    override void apply(string key, string value)
    {
        if (name == key)
        {
            if (type == "boolean")
            {
                if (value == "on")
                {
                    value = "true";
                }
                else if (value == "off")
                {
                    value = "false";
                }
            }
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

class MinMaxWithDefault(T) : WithDefault!(T)
{
    T min;
    T max;
    this(string name, string type, T value, T defaultValue, T min, T max)
    {
        super(name, type, value, defaultValue);
        this.min = min;
        this.max = max;
    }

    override Json toJson(string prefix)
    {
        // dfmt off
        return Json([
                        "name" : Json(path(prefix, name)),
                        "type" : Json(type),
                        "value" : Json(value),
                        "defaultValue" : Json(defaultValue),
                        "min" : Json(min),
                        "max" : Json(max),
                    ]);
        // dfmt on
    }
}

static minMaxWithDefault(T)(string name, string type, T v, T min, T max)
{
    return new MinMaxWithDefault!(T)(name, type, v, v, min, max);
}

static minMaxWithDefault(T)(string name, string type, T v, T defaultValue, T min, T max)
{
    return new MinMaxWithDefault!(T)(name, type, v, defaultValue, min, max);
}

class Renderer
{
    string name;
    WithDefault!bool active;
    MinMaxWithDefault!ubyte alpha;
    Property[] properties;
    Renderer[] childs;
    this(string name, Property[] properties)
    {
        this(name, properties, []);
    }

    this(string name, Property[] properties, Renderer[] childs)
    {
        this.name = name;
        this.active = withDefault("active", "boolean", true);
        this.alpha = minMaxWithDefault("alpha", "ubyte", cast(ubyte) 255,
                cast(ubyte) 255, cast(ubyte) 0, cast(ubyte) 255);
        this.properties = properties ~ active ~ alpha;
        this.childs = childs;
    }

    bool isActive()
    {
        return active.value;
    }

    void toggle()
    {
        active.value = !active.value;
    }

    private Json[] collectProperties(string prefix)
    {
        auto path = path(prefix, name);
        Json[] res;
        res ~= properties.map!(p => p.toJson(path)).array;
        foreach (child; childs)
        {
            res ~= child.collectProperties(path);
        }
        return res;
    }

    Json toJson(string prefix)
    {
        auto path = path(prefix, name);
        auto res = Json(["name": Json(path)]);

        auto allProperties = collectProperties(prefix);
        if (!allProperties.empty)
        {
            res["properties"] = Json(allProperties);
        }
        return res;
    }

    final Color[] render(uint size)
    {
        Color[] res;
        res.length = size;
        if (!isActive)
        {
            return res;
        }
        return internalRender(res);
    }

    abstract Color[] internalRender(Color[] destination);

    void dispatch(string[string[]] pathToValueMap)
    {
        info("dispatch on %s: %s".format(name, pathToValueMap));
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
            info("apply(", path, ", ", value);
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
        active.value = true;
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

    override Color[] internalRender(Color[] res)
    {
        const size = res.length;
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
    MinMaxWithDefault!float velocity;
    float phase = 0.0f;
    this(string name)
    {
        this.velocity = minMaxWithDefault("velocity", "float", 0.2f, 0.2f, -3.0f, 3.0f);
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

    override Color[] internalRender(Color[] res)
    {
        const size = res.length;
        import std.range;

        phase += velocity.value;
        float s = size.to!float;
        // dfmt off
        return iota(0, size)
            .map!(x => Color.hsv(hue(phase + (x.to!float * 360.0f / s))).setAlpha(alpha.value))
            .array;
        // dfmt on
    }
}

class SinRenderer : Renderer
{
    Color color;
    float phase;
    MinMaxWithDefault!float frequency;
    MinMaxWithDefault!float velocity;

    this(string name, string color, float phase, float frequency, float velocity)
    {
        this.frequency = minMaxWithDefault("frequency", "float", frequency,
                frequency, 1.0f, 10.0f);
        this.velocity = minMaxWithDefault("velocity", "float", velocity, velocity, -3.0f, 3.0f);
        super(name, [this.frequency, this.velocity]);
        this.color = Color(color);
        this.phase = phase;
    }

    override Color[] internalRender(Color[] res)
    {
        import std.range;
        import std.math;

        const size = res.length;

        phase += velocity.value;
        return iota(0, size).map!(
                x => color.factor(
                (sin((x.to!float + phase) / size * 2 * PI * frequency.value) + 1) / 2.0f)).array;
    }
}

class SumRenderer : Renderer
{
    this(string name, Renderer[] childs)
    {
        super(name, [], childs);
    }

    override Color[] internalRender(Color[] res)
    {
        auto colors = childs.map!(c => c.internalRender(res)).array;
        foreach (idx, ref color; res)
        {
            auto c = Color(cast(ubyte)(alpha.value), 0, 0, 0);
            foreach (childColors; colors)
            {
                c.add(childColors[idx]);
            }
            color = c;
        }
        return res;
    }
}

class DummyRenderer : Renderer
{
    this()
    {
        super("dummy", []);
    }

    override Color[] internalRender(Color[] res)
    {
        return res;
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

auto toPath(string key)
{
    return key.split(".").array.idup;
}

@("toPath") unittest
{
    import unit_threaded;

    "a.b.c".toPath.shouldEqual(["a", "b", "c"]);
}

void renderloop(immutable(Prefs) settings)
{
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
            new ColorRenderer("read", "#ff0000"),
            new ColorRenderer("green", "#00ff00"),
            new ColorRenderer("blue", "#0000ff"),
            new RainbowRenderer("rainbow"),
            new SumRenderer("fire", [
                                new SinRenderer("red", "#ff0000", 0, 4, 2),
                                new SinRenderer("yellow", "#ffff00", 0, 2, -1),
                            ]),
        ];
        // dfmt on
        Renderer currentRenderer = new DummyRenderer;
        auto timer = new Timer("rendering").start;
        scope (exit)
        {
            timer.shutdown();
        }

        Tid[] renderListener;

        int renderId = 0;
        while (!finished)
        {
            bool rendering = false;
            // dfmt off
            receive(
                (Tid sender, GetState s)
                {
                    immutable res = Json(
                        [
                            "current": Json(["name" : Json(currentRenderer.name), "active" : Json(currentRenderer.isActive)]),
                            "renderers": Json(renderers.map!(r => r.toJson("")).array),
                        ]
                    );

                    sender.send(cast(immutable)GetState.Result(res));
                },
                (Tid sender, Toggle toggle)
                {
                    currentRenderer.toggle;
                    sender.send(Toggle.Result());
                },
                (Tid sender, Register register) {
                    renderListener ~= sender;
                    writeln("renderlistener: ", renderListener.length);
                },
                (Tid sender, immutable(Activate) activate)
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
                    sender.send(Activate.Result());
                    foreach (tid; renderListener) {
                        tid.send(thisTid, RendererChanged(activate.profile));
                    }
                },
                (Tid sender, Set set)
                {
                    info("setting ", set);
                    // transform from string[string] to string[path]
                    string[string[]] pathToValueMap;
                    foreach (key, value; set.data.byKeyValue) {
                        pathToValueMap[key.toPath] = value.to!string;
                    }
                    currentRenderer.dispatch(pathToValueMap);
                    sender.send(set.Result(true));
                },
                (Tid sender, Apply apply)
                {
                    currentRenderer.apply(apply.key.toPath, apply.value);
                    sender.send(apply.Result(true));
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
                (OwnerTerminated ot)
                {
                    finished = true;
                },
                (Variant v) {
                    error("unknown message ", v);
                },
            );
            // dfmt on
        }
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
