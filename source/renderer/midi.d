module renderer.midi;
import renderer;
import std.datetime.stopwatch;
import prefs;

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
        info("spawning thread for midi");

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
                error("Midi.serverCommunication - problems while talking to %s:%s".format(host,
                        port), t);
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

        info("spawning thread for midi");
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

                (Tid sender, GetName request) {
                    sender.send(request.Result(name));
                },
                (Tid sender, Render request)
                {
                    try
                    {
                        auto values = (cast(Signal[])notes).map!(note => noteToFloat(note));
                        auto y = cast(immutable float[])(values.array);
                        auto interpolator = linear!float(x.sliced, y.sliced);

                        sender.send(
                            request.Result(
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
                (Tid sender, GetProperties request) {
                    sender.send(request.Result());
                },
                (Tid sender, Apply request) {
                    sender.send(request.Result(true));
                },
                (Tid sender, Shutdown s)
                {
                    shutdownAndWait(serverCommunication);
                    shutdown = true;
                    sender.send(s.Result());
                },
                (LinkTerminated t)
                {
                    info("communicate to server finished");
                },
                (OwnerTerminated t)
                {
                    info("render received OwnerTerminated");
                },
                (Variant v) {
                    warning("unhandled ", v);
                }
                    );
            // dfmt on

        }

        info("Midi.render finishing");
    }
}
