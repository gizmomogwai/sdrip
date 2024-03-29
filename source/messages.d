module messages;

import std.concurrency;
import vibe.data.json;
import state;

struct Toggle
{
    struct Result
    {
        bool result;
    }
}

struct Shutdown
{
}

struct Apply
{
    string key;
    string value;
    struct Result
    {
        bool result;
    }
}

struct Register
{
    Tid tid;
}

struct RendererChanged
{
    string name;
}

struct Activate
{
    string profile;
    struct Result
    {
        bool result;
    }
}

struct Set
{
    Json data;
    struct Result
    {
        bool result;
    }
}

struct GetState
{
    struct Result
    {
        Json result;
    }
}

import std.traits : Fields;

auto sendReceive(Request)(Tid to, Fields!Request parameters) @trusted
{
    to.send(thisTid, cast(immutable) Request(parameters));
    Request.Result res;
    receive((immutable(Request.Result) r) { res = r; });
    return res.result;
}

void shutdownChild(std.concurrency.Tid tid)
{
    import std.stdio;

    tid.send(thisTid, Shutdown());
    receive((LinkTerminated l) { writeln("link terminated"); });
}
