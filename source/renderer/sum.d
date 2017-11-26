module renderer.sum;
import renderer;
import std.algorithm;
import std.range;

class Sum : Renderer
{

    Renderer[] children;

    public this(string name, uint nrOfLeds, Renderer[] children)
    {
        super(name, nrOfLeds);
        this.children = children;
    }

    public override Tid internalStart()
    {
        auto childrenTids = children.map!(child => child.start).array;
        info("spawning thread for sum");
        return spawnLinked(&render, name, nrOfLeds, cast(immutable(Tid)[])(childrenTids));
    }

    static void render(string name, uint nrOfLeds, immutable(Tid)[] children)
    {
        try
        {
            auto impl = new SumImpl(name, nrOfLeds, children);
            while (!impl.finished)
            {
                // dfmt off
                receive(
                    &impl.sendName,
                    &impl.render,
                    &impl.properties,
                    &impl.apply,
                    &impl.shutdown,
                    &impl.unhandled
                );
                // dfmt on

            }

            info("Sum.render finishing");
        }
        catch (Throwable t)
        {
            error(t);
        }
    }

}

static class SumImpl : RendererImpl
{
    import std.math;

    immutable(Tid)[] children;
    Color[] colors;

    this(string name, uint nrOfLeds, immutable(Tid)[] children)
    {
        super(name, nrOfLeds);
        this.children = children;
        this.colors = new Color[nrOfLeds];
    }

    public override immutable(Color)[] internalRender()
    {
        foreach (tid; children)
        {
            (cast(Tid) tid).send(thisTid, Render());
        }

        foreach (tid; children)
        {
            receive((Render.Result r) {
                for (int i = 0; i < colors.length; ++i)
                {
                    colors[i].add(r.data[i]);
                }
            });
        }

        return colors.dup;
    }

    override public Property[] internalProperties(Prefix prefix)
    {
        auto res = appender!(Property[]);

        foreach (tid; children)
        {
            trace("checking one child");
            try
            {

                (cast(Tid) tid).send(thisTid, GetProperties(prefix));
                receive((GetProperties.Result r) {
                    res.put(cast(Property[]) r.result);
                });
            }
            catch (Throwable t)
            {
                error(t);
            }
        }
        return res.data;
    }

    protected override bool internalApply(immutable(string)[] path, string value)
    {
        if (super.internalApply(path, value))
        {
            return true;
        }

        if (path[0] != name)
        {
            return false;
        }

        auto pathForChilds = path[1 .. $];
        // TODO map
        foreach (c; children)
        {
            Tid child = (cast(Tid) c);
            auto name = child.sendReceive!(GetName)();
            if (name == pathForChilds[0])
            {
                bool res = child.sendReceive!(Apply)(pathForChilds, value);
                if (!res)
                {
                    return false;
                }
            }
        }
        return true;
    }
}
