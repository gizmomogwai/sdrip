module misc.miditest;

import std.conv;
import std.socket;
import std.stdio;
import undead.socketstream;

int miditest(string[] args)
{
    auto s = new TcpSocket(getAddress(args[1], args[2].to!ushort)[0]);
    auto stream = new SocketStream(s);
    while (true)
    {
        ubyte length;
        stream.read(length);
        writeln("length of paket: ", length);
        for (int i = 0; i < length; ++i)
        {
            ubyte data;
            stream.read(data);
            write(data);
        }
        writeln();
    }
}
