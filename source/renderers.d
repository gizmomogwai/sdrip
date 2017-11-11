module renderers;

import std.concurrency;
import std.datetime.stopwatch;
import dotstar;
import sdrip;
import std.experimental.logger;
import std.algorithm;
import messages;
import std.range;
import std.string;
import std.conv;
import std.stdio; // TODO remove
import prefs;

class RendererImpl
{
    string name;
    uint nrOfLeds;
    bool active;
    this(string name, uint nrOfLeds) {
        this.name = name;
        this.nrOfLeds = nrOfLeds;
    }
    public abstract immutable(Color)[] render();
    public abstract immutable(Property)[] properties(Prefix prefix);
    public bool apply(immutable(string)[] path, string value)
    {
        if (path.length != 2) {
            return false;
        }
        if (path[0] != name) {
            return false;
        }

        if (path[1] == "active") {
            active = value.to!bool;
            return true;
        }

        return false;
    }
}

/+
 public override Property[] properties() const @safe
 {
 auto res = super.properties();
 res ~= new ColorProperty("color", color, defaultColor);
 res ~= new RangeProperty("frequency", 0.1f, 5f, frequency, defaultFrequency);
 res ~= new RangeProperty("speed", -10.0f, 10.0f, speed, defaultSpeed);
 return res;
 }

 public override bool apply(string[] key, string value)
 {
 switch (key[0])
 {
 case "color":B
 color = value.to!Pixel;
 return true;
 case "frequency":
 frequency = value.to!float;
 return true;
 case "speed":
 speed = value.to!float;
 return true;
 default:
 break;
 }
 return super.apply(key, value);
 }

 }
 +/
class Dummy : Renderer
{
    public this(uint nrOfLeds)
    {
        super("dummy", nrOfLeds);
    }

    public override Tid internalStart()
    {
        return spawnLinked(&done);
    }

    static void done()
    {
    }
}

static class SinImpl : RendererImpl
{
    import std.math;

    WithDefault!Color color;
    WithDefault!float frequency;
    WithDefault!float velocity;
    float phase;

    this(string name, uint nrOfLeds, WithDefault!Color color,
         WithDefault!float frequency, WithDefault!float velocity)
    {
        super(name, nrOfLeds);
        this.nrOfLeds = nrOfLeds;
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

    public override immutable(Color)[] render()
    {
        phase += velocity.value;
        // dfmt off
        return iota(0, nrOfLeds)
            .map!(x => (sin((x * frequency.value + phase) / nrOfLeds * 2 * PI) + 1) / 2)
            .map!(x => floatToColor(x))
            .array
            .idup;
        // dfmt on
    }

    public override immutable(Property)[] properties(Prefix prefix)
    {
        Property[] res;
        res ~= new ColorProperty(prefix.add("color").to!string, color);
        return cast(immutable(Property)[]) res;
    }

    public override bool apply(immutable(string)[] path, string value)
    {
        if (super.apply(path, value))
        {
            return true;
        }

        if (path.length != 2) {
            return false;
        }
        if (path[0] != name) {
            return false;
        }

        if (path[1] == "color") {
            color.value = value.to!Color;
            return true;
        }

        warning("%s†%s not supported".format(__MODULE__, path));
        return false;
    }

}

class Sin : Renderer
{
    WithDefault!Color color;
    WithDefault!float frequency;
    WithDefault!float velocity;
    public this(string name, uint nrOfLeds, Color color, float frequency, float velocity)
    {
        super(name, nrOfLeds);
        this.color = withDefault(color);
        this.frequency = withDefault(frequency);
        this.velocity = withDefault(velocity);
    }

    public override Tid internalStart()
    {
        return spawnLinked(&render, name, nrOfLeds, color, frequency, velocity);
    }

    static void render(string name, uint nrOfLeds, WithDefault!Color color,
                       WithDefault!float frequency, WithDefault!float velocity)
    {
        try
        {
            auto impl = new SinImpl(name, nrOfLeds, color, frequency, velocity);
            bool finished = false;
            while (!finished)
            {
                // dfmt off
                receive(
                    (Tid sender, GetName request)
                    {
                        sender.send(request.Result(name));
                    },
                    (Tid sender, Render request)
                    {
                        sender.send(request.Result(impl.render));
                    },
                    (Tid sender, GetProperties request)
                    {
                        auto res = impl.properties(request.prefix.add(name));
                        sender.send(request.Result(res));
                    },
                    (Tid sender, Shutdown request)
                    {
                        finished = true;
                        sender.send(request.Result());
                    },
                    (Tid sender, Apply request)
                    {
                        sender.send(request.Result(impl.apply(request.path, request.value)));
                    },
                    (OwnerTerminated t)
                    {
                        info("render received OwnerTerminated");
                        finished = true;
                    },
                    (Variant v) {
                        error("Unknown message received: ", v);
                    });
                // dfmt on

            }

            info("Sin.render finishing");
        }
        catch (Throwable t)
        {
            error(t);
        }
    }

}

class Midi : Renderer
{
    import undead.socketstream;
    import std.socket;

    immutable string host;
    immutable ushort port;

    /++
     + my piano delivery notes from 21 to 108. velocity from 0 to 120
     +/
    const static uint MIN_NOTE = 21;
    const static uint MAX_NOTE = 108;
    struct Signal
    {
        public StopWatch age;
        public float velocity = 0.0f;
        public string toString()
        {
            return "Signal(velocity: %s, age: %sms)".format(velocity, age.peek);
        }
    }

    public this(string name, uint nrOfLeds, immutable(Prefs) settings)
    {
        super(name, nrOfLeds);
        this.host = settings.get("midi_server_host");
        this.port = settings.get("midi_server_port").to!ushort;
    }

    public override Tid internalStart()
    {
        return spawnLinked(&render, name, nrOfLeds, host, port);
    }

    static bool checkForShutdown()
    {
        bool res = false;

        bool gotSomething = true;
        while (gotSomething)
        {
            // dfmt off
            gotSomething = receiveTimeout(0.msecs,
                                          (Tid tid, Shutdown s)
                                          {
                                              info("shutting down connection to server");
                                              res = true;
                                          },
                                          (OwnerTerminated t)
                                          {
                                              info("communicateToServer received OwnerTerminated");
                                              res = true;
                                          });
            // dfmt on
        }
        return res;
    }

    static void communicateToServer(Tid renderer, string host, ushort port)
    {
        bool shutdown = false;
        while (!shutdown)
        {
            try
            {
                auto s = new TcpSocket(getAddress(host, port)[0]);
                auto stream = new SocketStream(s);

                void skipMidi(SocketStream stream, ubyte l)
                {
                    for (auto i = 0; i < l; ++i)
                    {
                        ubyte trash;
                        stream.read(trash);
                    }
                }

                while (!shutdown)
                {
                    ubyte length;
                    stream.read(length);
                    if (length == 3)
                    {
                        ubyte command;
                        stream.read(command);
                        if (command == 0x90)
                        {
                            ubyte note;
                            stream.read(note);
                            ubyte velocity;
                            stream.read(velocity);

                            renderer.send(Note(note, velocity));
                        }
                        else
                        {
                            skipMidi(stream, 2);
                        }
                    }
                    else
                    {
                        skipMidi(stream, length);
                    }
                    shutdown = checkForShutdown();
                }
            }
            catch (Throwable t)
            {
                error("Midi.serverCommunication", t);
                import core.thread;

                Thread.sleep(1.seconds);
                shutdown = checkForShutdown();
            }
        }
    }

    static void render(string name, uint nrOfLeds, string host, ushort port)
    {
        import mir.ndslice : sliced;
        import mir.interpolate.linear : linear;

        Signal[MAX_NOTE - MIN_NOTE + 1] notes;
        auto h = new float[notes.length];
        for (int i = 0; i < notes.length; ++i)
        {
            h[i] = i.to!float;
        }
        auto x = cast(immutable float[]) h;

        Tid serverCommunication = spawnLinked(&communicateToServer, thisTid, host.idup, port);

        bool shutdown = false;
        while (!shutdown)
        {
            auto noteToFloat(Signal note)
            {
                import core.time;

                auto age = note.age.peek;
                float factor = max(0, 1 - (age.total!"msecs" / 3_000.0f));
                return max(0.0f, min(254.0f, (note.velocity * 3) * factor));
            }

            auto floatToColor(float f)
            {
                return Color(cast(ubyte) f, cast(ubyte) 0, cast(ubyte) 0);
            }
            // dfmt off

            receive(
                (Note note)
                {
                    try
                    {
                        if (note.velocity > 0)
                        {
                            notes[note.note - MIN_NOTE].age.reset();
                            notes[note.note - MIN_NOTE].age.start();
                            notes[note.note - MIN_NOTE].velocity = note.velocity;
                        }
                    }
                    catch (Throwable t)
                    {
                        info(t);
                    }
                },
                (Tid sender, Render request)
                {
                    try
                    {
                        auto values = (cast(Signal[])notes).map!(note => noteToFloat(note));
                        auto y = cast(immutable float[])(values.array);
                        auto interpolator = linear!float(x.sliced, y.sliced);

                        sender.send(request.Result(
                                        iota(0, nrOfLeds)
                                        .map!(i => i.to!float)
                                        .map!(f => f / nrOfLeds * notes.length) // nrOfLeds 120, keys 87
                                        .map!(f => interpolator(f))
                                        .map!(f => floatToColor(f))
                                        .array.idup));
                    }
                    catch (Throwable t)
                    {
                        error("problem ", t);
                    }
                },
                (LinkTerminated t)
                {
                    info("communicate to server finished");
                },
                (Tid tid, Shutdown s)
                {
                    shutdownAndWait(serverCommunication);
                    shutdown = true;
                },
                (OwnerTerminated t)
                {
                    info("render received OwnerTerminated");
                });
            // dfmt on

        }

        info("Midi.render finishing");
    }
}

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
        return spawnLinked(&render, name, nrOfLeds, cast(immutable(Tid)[])(childrenTids));
    }

    static void render(string name, uint nrOfLeds, immutable(Tid)[] children)
    {
        try
        {
            auto impl = new SumImpl(name, nrOfLeds, children);
            bool finished = false;
            while (!finished)
            {
                // dfmt off
                receive(
                    (Tid sender, Render request)
                    {
                        sender.send(Render.Result(impl.render));
                    },
                    (Tid sender, GetProperties request)
                    {
                        sender.send(request.Result(impl.properties(request.prefix.add(name))));
                    },
                    (Tid sender, Apply apply)
                    {
                        info("");
                        sender.send(Apply.Result(impl.apply(apply.path, apply.value)));
                    },
                    (OwnerTerminated t)
                    {
                        /*
                          info("render received OwnerTerminated");
                          finished = true;
                        */
                    },
                    (Variant v) {
                        error("cannot work with ", v);
                    });
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
        this.name = name;
        this.children = children;
        this.colors = new Color[nrOfLeds];
    }

    public override immutable(Color)[] render()
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

    override public immutable(Property)[] properties(Prefix prefix)
    {
        info("");
        auto res = appender!(immutable(Property)[]);

        foreach (tid; children) {
            trace("checking one child");
            try {

                (cast(Tid) tid).send(thisTid, GetProperties(prefix));
                receive((GetProperties.Result r) {
                        res.put(r.result);
                    });
            } catch (Throwable t) {
                error(t);
            }
        }
        return cast(immutable(Property)[]) res.data;
    }

    public override bool apply(immutable(string)[] path, string value)
    {
        if (super.apply(path, value))
        {
            return true;
        }

        if (path[0] != name) {
            return false;
        }

        auto pathForChilds = path[1..$];
        // TODO map
        foreach (c; children) {
            Tid child = (cast(Tid)c);
            auto name =child.sendReceive!(GetName)();
            if (name == pathForChilds[0]) {
                bool res = child.sendReceive!(Apply)(pathForChilds, value);
                if (!res) {
                    return false;
                }
            }
        }
        return true;
    }

}
