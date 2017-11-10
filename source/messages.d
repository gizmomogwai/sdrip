module messages;

struct SetGenerator
{
}

struct GetProperties
{
    struct Result
    {
        import sdrip;

        immutable(Property)[] result;
    }
}

struct SetProperties
{
    immutable(string)[] path;
    string value;
    struct Result
    {
        bool result;
    }
}

struct Shutdown
{
    struct Result
    {
    }
}

struct Note
{
    ubyte note;
    ubyte velocity;
}

struct Render
{
    struct Result
    {
        import dotstar;

        immutable(Color)[] data;
    }
}

import std.concurrency : Tid;

void shutdownChild(Tid tid)
{
    import std.concurrency;

    tid.send(thisTid, Shutdown());
    receive((LinkTerminated l) {  });
}

void shutdownAndWait(Tid tid)
{
    import std.concurrency;

    tid.send(thisTid, Shutdown());
    receive((Shutdown.Result r) {  });
}
