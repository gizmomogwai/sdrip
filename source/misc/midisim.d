module misc.midisim;

import core.thread;
import std.socket;
import std.stdio;
import undead.socketstream;

int midisim(string[] args)
{
    auto server = new TcpSocket();
    server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    server.bind(new InternetAddress(55554));
    server.listen(1);

    while (true)
    {
        auto client = server.accept();
        auto stream = new SocketStream(client);

        ubyte note = 21;
        ubyte velocity = 0;
        try
        {
            while (true)
            {
                Thread.sleep(50.msecs);

                writeln("sending a midi packet");
                stream.write(cast(ubyte) 3);
                stream.write(cast(ubyte) 0x90);
                stream.write(note);
                stream.write(velocity);

                note++;
                velocity += 2;
                if (note > 108)
                {
                    note = 21;
                }
                if (velocity > 120)
                {
                    velocity = 0;
                }
                writeln("note sent ", note, " with ", velocity);
            }
        }
        catch (Exception e)
        {
            writeln(e);
        }
    }
}
