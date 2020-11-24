module restinterface;

import state;
import messages;
import std.concurrency;
import vibe.data.json;

interface Api
{
    Json getState() @safe;
    Json postActivate(string renderer) @safe;
    Json putSet(Json data) @safe;

    bool postShutdown() @safe;
}

class RestInterface : Api
{
    Tid theRenderer;

    this(Tid renderer)
    {
        this.theRenderer = renderer;
    }

    Json getState()
    {
        return theRenderer.sendReceive!GetState;
    }

    Json postActivate(string renderer)
    {
        import std.stdio;
        import std.conv;
        writeln(renderer.to!string);
        // TODO remove debug info
        
        internalActivate(renderer);
        return theRenderer.sendReceive!GetState;
    }

    private void internalActivate(string renderer) @trusted
    {
        theRenderer.sendReceive!Activate(renderer);
    }

    Json putSet(Json data)
    {
        internalPutSet(data);
        return theRenderer.sendReceive!GetState;
    }

    private void internalPutSet(Json data) @trusted
    {
        theRenderer.sendReceive!Set(data);
    }

    bool postShutdown()
    {
        internalShutdown();
        return true;
    }

    private void internalShutdown() @trusted
    {
        import vibe.core.core;

        exitEventLoop();
    }
}
