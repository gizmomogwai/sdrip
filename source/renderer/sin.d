/// sinus
module renderer.sin;

import renderer;
import std.algorithm;
import std.conv;
import std.range;
import std.string;

class SinImpl : RendererImpl
{
    import std.math;

    WithDefault!Color color;

    MinMaxWithDefault!float frequency;
    MinMaxWithDefault!float velocity;
    float phase;

    this(string name, uint nrOfLeds, WithDefault!Color color,
            MinMaxWithDefault!float frequency, MinMaxWithDefault!float velocity)
    {
        super(name, nrOfLeds);
        this.color = color;
        this.frequency = frequency;
        this.velocity = velocity;
        this.phase = 0f;
    }

    auto floatToColor(float f)
    {
        return Color(cast(ubyte)(f * color.value.r),
                cast(ubyte)(f * color.value.g), cast(ubyte)(f * color.value.b));
    }

    float f(float x)
    {
        return max(0, pow(sin(x), 3));
    }

    protected override immutable(Color)[] internalRender()
    {
        phase += velocity.value;
        // dfmt off
        return iota(0, nrOfLeds)
            .map!(x => (f((x * frequency.value + phase) / nrOfLeds * 2 * PI)))
            .map!(x => floatToColor(x))
            .array
            .idup;
        // dfmt on
    }

    protected override Property[] internalProperties(Prefix prefix)
    {
        Property[] res = super.internalProperties(prefix);
        res ~= new ColorProperty(prefix.add("color").to!string, color);
        res ~= new FloatProperty(prefix.add("frequency").to!string, frequency);
        res ~= new FloatProperty(prefix.add("velocity").to!string, velocity);
        return res;
    }

    protected override bool internalApply(immutable(string)[] path, string value)
    {
        if (super.internalApply(path, value))
        {
            return true;
        }

        if (path.length != 2)
        {
            return false;
        }
        if (path[0] != name)
        {
            return false;
        }

        switch (path[1]) {
        case "color":
            color.value = value.to!Color;
            return true;
        case "frequency":
            frequency.value = value.to!float;
            return true;
        case "velocity":
            velocity.value = value.to!float;
            return true;
        default:
            warning("%s†%s not supported".format(__MODULE__, path));
            return false;
        }
    }

}

class Sin : Renderer
{
    WithDefault!Color color;
    MinMaxWithDefault!float frequency;
    MinMaxWithDefault!float velocity;
    public this(string name, uint nrOfLeds, Color color,
            MinMaxWithDefault!float frequency, MinMaxWithDefault!float velocity)
    {
        super(name, nrOfLeds);
        this.color = withDefault(color);
        this.frequency = frequency;
        this.velocity = velocity;
    }

    public override Tid internalStart()
    {
        info("spawning thread for sin");
        return spawnLinked(&render, name, nrOfLeds, color, frequency, velocity);
    }

    static void render(string name, uint nrOfLeds, WithDefault!Color color,
            MinMaxWithDefault!float frequency, MinMaxWithDefault!float velocity)
    {
        scope (exit)
        {
            info("Finishing renderthread of sin");
        }
        import core.thread;

        Thread.getThis.name = "sin(%s)".format(name);

        try
        {
            auto impl = new SinImpl(name, nrOfLeds, color, frequency, velocity);
            while (!impl.finished())
            {
                // dfmt off
                receive(
                    &impl.sendName,
                    &impl.render,
                    &impl.properties,
                    &impl.apply,
                    &impl.shutdown,
                    &impl.ownerTerminated,
                    &impl.unhandled
                );
                // dfmt on

            }

        }
        catch (Throwable t)
        {
            error(t);
        }
    }

}
