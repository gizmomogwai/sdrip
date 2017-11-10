module tcpreceiver;
import dyaml;
import undead.socketstream;
import std.socket;
import dotstar;
import std.experimental.logger;
import prefs;
import std.conv;

int receive(string[] args)
{

    auto settings = prefs.load("settings.yaml");
    auto nrOfLeds = settings.get("nr_of_leds").to!uint;
    auto strip = new SpiStrip(nrOfLeds);

    auto server = new TcpSocket();
    server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    server.bind(new InternetAddress(55555));
    server.listen(1);

    while (true)
    {
        try
        {
            info("waiting for next client");
            auto client = server.accept();
            auto stream = new SocketStream(client);
            stream.write(nrOfLeds);
            ubyte[] data = new ubyte[nrOfLeds * 4];
            while (true)
            {
                auto read = stream.read(data);
                if (read == 0)
                {
                    break;
                }

                for (int idx = 0; idx < nrOfLeds; ++idx)
                {
                    auto i = idx * 4;
                    strip.set(idx, data[i], data[i + 1], data[i + 2], data[i + 3]);
                }
                info(".");
                strip.refresh();
            }

        }
        catch (Exception e)
        {
            error(e);
        }
    }
}
