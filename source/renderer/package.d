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
    private bool active;
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

    public bool finished()
    {
        return pleaseShutdown;
    }

    public void render(Tid sender, Render request)
    {
        sender.send(Render.Result(internalRender));
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
        res ~= new BoolProperty(prefix.add("active").to!string, withDefault(active));
        return res;
    }

    public void apply(Tid sender, Apply request)
    {
        sender.send(request.Result(internalApply(request.path, request.value)));
    }

    protected bool internalApply(immutable(string)[] path, string value)
    {
        import std.conv;

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
            active = value.to!bool;
            return true;
        }

        return false;
    }
}
