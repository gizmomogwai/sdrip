module restinterface;

import state;
import messages;
import std.concurrency;
import vibe.data.json;

interface Api
{
    Json getState() @safe;
    void activate(string profile) @safe;
    void postSet(Json data) @safe;

    void postShutdown() @safe;
}

class RestInterface : Api
{
    Tid renderer;

    this(Tid renderer)
    {
        this.renderer = renderer;
    }

    Json getState()
    {
        return sendReceive!GetState(renderer);
    }

    void activate(string profile)
    {
        internalActivate(profile);
    }

    private void internalActivate(string profile) @trusted
    {
        import std.stdio, std.string;

        writeln("activating profile=%s on renderer=%s".format(profile, renderer));
        std.concurrency.send(renderer, thisTid, Activate(profile));
    }

    void postSet(Json data)
    {
        internalPostSet(data);
    }

    private void internalPostSet(Json data) @trusted
    {
        import std.stdio;

        writeln(data);
        renderer.send(thisTid, Set(data));
    }

    void postShutdown()
    {
        internalShutdown();
    }

    private void internalShutdown() @trusted
    {
        import vibe.core.core;

        exitEventLoop();
    }
}
