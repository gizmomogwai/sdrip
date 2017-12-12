/// rainbow colors
module renderer.rainbow;

import renderer;
import sdrip;
import std.algorithm;
import std.conv;
import std.range;
import std.string;

class RainbowImpl : RendererImpl
{
    import std.math;

    MinMaxWithDefault!float velocity;
    float phase = 0;

    this(string name, uint nrOfLeds, MinMaxWithDefault!float velocity)
    {
        super(name, nrOfLeds);
        this.velocity = velocity;
    }

    int hue(float v)
    {
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

    protected override immutable(Color)[] internalRender()
    {
        phase += velocity.value;
        // dfmt off
        return iota(0, nrOfLeds)
            .map!(x => Color.hsv(hue(phase + (x.to!float * 360.0f / nrOfLeds.to!float))))
            .array
            .idup;
        // dfmt on
    }

    protected override Property[] internalProperties(Prefix prefix)
    {
        Property[] res = super.internalProperties(prefix);
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

        if (path[1] == "velocity")
        {
            velocity.value = value.to!float;
            return true;
        }

        warning("%s†%s not supported".format(__MODULE__, path));
        return false;
    }

}

class Rainbow : Renderer
{
    MinMaxWithDefault!float velocity;
    public this(string name, uint nrOfLeds, MinMaxWithDefault!float velocity)
    {
        super(name, nrOfLeds);
        this.velocity = velocity;
    }

    public override Tid internalStart()
    {
        info("spawning thread for rainbow");
        return spawnLinked(&render, name, nrOfLeds, velocity);
    }

    static void render(string name, uint nrOfLeds, MinMaxWithDefault!float velocity)
    {
        scope (exit)
        {
            info("Finishing renderthread of rainbow");
        }
        import core.thread;

        Thread.getThis.name = "rainbow(%s)".format(name);

        try
        {
            auto impl = new RainbowImpl(name, nrOfLeds, velocity);
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
