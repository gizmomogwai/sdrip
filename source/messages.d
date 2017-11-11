module messages;

struct SetRenderer
{
}

struct GetName
{
    struct Result {
        string result;
    }
}
struct Activate
{
    string name;
    struct Result
    {
        bool result;
    }
}
struct Index
{
    struct Result
    {
        struct Data
        {
            string current;
            immutable(string)[] renderer;
        }

        Data result;
    }
}

struct GetCurrent
{
    struct Result
    {
        string result;
    }
}

struct Prefix {
    immutable(string)[] path;
    Prefix add(string part) {
        return Prefix(path ~ part);
    }
    string toString() {
        import std.array;
        return path.join(".");
    }
}

struct GetProperties
{
    Prefix prefix;
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

struct Apply {
    immutable(string)[] path;
    string value;

    struct Result {
        bool result;
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
