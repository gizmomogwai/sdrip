module renderer;
public import dotstar;
public import messages;
public import sdrip;
public import std.algorithm;
public import std.array;
public import std.concurrency;
public import std.conv;
public import std.experimental.logger;
public import std.range;
public import std.string;

class Renderer
{
    immutable string name;
    immutable uint nrOfLeds;
    Tid renderer;

    this(string name, uint nrOfLeds)
    {
        this.name = name;
        this.nrOfLeds = nrOfLeds;
    }

    public final Tid start()
    {
        renderer = internalStart();
        return renderer;
    }

    protected abstract Tid internalStart();
}

class RendererImpl
{
    protected const string name;
    protected const uint nrOfLeds;
    private WithDefault!bool active = withDefault(true);
    private bool pleaseShutdown = false;
    this(string name, uint nrOfLeds)
    {
        this.name = name;
        this.nrOfLeds = nrOfLeds;
    }

    public void unhandled(Variant v)
    {
        error("Unknown message received: ", v);
    }

    public void sendName(Tid sender, GetName request)
    {
        sender.send(request.Result(name));
    }

    public void shutdown(Tid sender, Shutdown request)
    {
        pleaseShutdown = true;
        sender.send(request.Result());
    }

    public void ownerTerminated(OwnerTerminated t)
    {
        pleaseShutdown = true;
    }

    public bool finished()
    {
        return pleaseShutdown;
    }

    public void render(Tid sender, Render request)
    {
        if (active.value)
        {
            sender.send(Render.Result(internalRender));
        }
        else
        {
            sender.send(Render.Result(iota(0, nrOfLeds).map!(x => Color(0, 0, 0)).array.idup));
        }
    }

    protected abstract immutable(Color)[] internalRender();

    public void properties(Tid sender, GetProperties request)
    {
        sender.send(request.Result(cast(
                immutable(Property)[]) internalProperties(request.prefix.add(name))));
    }

    protected Property[] internalProperties(Prefix prefix)
    {
        Property[] res;
        res ~= new BoolProperty(prefix.add("active").to!string, active);
        return res;
    }

    public void apply(Tid sender, Apply request)
    {
        sender.send(request.Result(internalApply(request.path, request.value)));
    }

    protected bool internalApply(immutable(string)[] path, string value)
    {
        if (path.length != 2)
        {
            return false;
        }
        if (path[0] != name)
        {
            return false;
        }

        if (path[1] == "active")
        {
            active.value = value == "on" ? true : false;
            return true;
        }

        return false;
    }

}
