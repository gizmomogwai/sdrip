module dotstar;

import core.thread;
import std.conv;
import std.experimental.logger;
import std.socket;
import std.string;
import undead.socketstream;

extern (C)
{
    struct Spi
    {
    }

    Spi* createSpi();
    void destroySpi(Spi* spi);
    int writeSpi(Spi* spi, ubyte* pixels, uint nrOfPixels);
}

abstract class Strip
{
    ubyte[] ledBuffer;
    this(uint nrOfLeds)
    {
        this.ledBuffer = new ubyte[nrOfLeds * 4];
    }

    Strip set(uint idx, Color p)
    {
        auto i = idx * 4;
        ledBuffer[i] = p.a;
        ledBuffer[i + 1] = p.b;
        ledBuffer[i + 2] = p.g;
        ledBuffer[i + 3] = p.r;
        return this;
    }

    Strip set(uint idx, ubyte a, ubyte r, ubyte g, ubyte b)
    {
        auto i = idx * 4;
        ledBuffer[i] = a;
        ledBuffer[i + 1] = b;
        ledBuffer[i + 2] = g;
        ledBuffer[i + 3] = r;
        return this;
    }

    uint size()
    {
        return cast(uint) this.ledBuffer.length / 4;
    }

    public void print()
    {
        for (int i = 0; i < 1; ++i)
        {
            auto idx = i * 4;
            info("%d %d %d %d".format(ledBuffer[idx], ledBuffer[idx + 1],
                    ledBuffer[idx + 2], ledBuffer[idx + 3]));
        }
    }

    public override string toString()
    {
        return "Strip(%s)".format(ledBuffer.length / 4);
    }

    public void test()
    {
        for (int i = 0; i < size(); ++i)
        {
            set(i, Color(255, 0, 0));
        }
        refresh();
        Thread.sleep(dur!("seconds")(1));
        for (int i = 0; i < size(); ++i)
        {
            set(i, Color(0, 255, 0));
        }
        refresh();
        Thread.sleep(dur!("seconds")(1));
        for (int i = 0; i < size(); ++i)
        {
            set(i, Color(0, 0, 255));
        }
        refresh();
        Thread.sleep(dur!("seconds")(1));
    }

    abstract Strip refresh();
    abstract void close();
}

class SpiStrip : Strip
{
    Spi* spi;
    this(uint nrOfLeds)
    {
        super(nrOfLeds);
        this.spi = createSpi();
    }

    override Strip refresh()
    {
        int res = writeSpi(spi, ledBuffer.ptr, cast(uint) ledBuffer.length / 4);
        if (res != 0)
        {
            throw new Exception("write to spi failed: %d".format(res));
        }
        return this;
    }

    override void close()
    {
        destroySpi(spi);
    }
}

class TcpStrip : Strip
{

    SocketStream stream;
    this(uint nrOfLeds, string host)
    {
        super(nrOfLeds);
        auto s = new TcpSocket(getAddress(host, cast(ushort) 55555)[0]);
        stream = new SocketStream(s);
        uint ledsOnOtherSide;
        stream.read(ledsOnOtherSide);
        if (ledsOnOtherSide != nrOfLeds)
        {
            throw new Exception("remote led has %s leds but local one has %s".format(ledsOnOtherSide,
                    nrOfLeds));
        }
        info(__MODULE__, ":", __PRETTY_FUNCTION__, ":", __LINE__,
                " connected to ", host, " with ", nrOfLeds, " leds");
    }

    override Strip refresh()
    {
        info("refreshing");
        stream.write(ledBuffer);
        return this;
    }

    override void close()
    {
        stream.close();
    }
}

struct Color
{
    ubyte a = cast(ubyte) 0xff;
    ubyte r;
    ubyte g;
    ubyte b;
    this(string v) @safe
    {
        if (v.length != 7)
        {
            throw new Exception("illegal color string format: '%s' expected #rrggbb".format(v));
        }
        if (v[0 .. 1] != "#")
        {
            throw new Exception("illegal color string format: '%s' expected #rrggbb".format(v));
        }
        a = cast(ubyte) 0xff;
        r = v[1 .. 3].to!ubyte(16);
        g = v[3 .. 5].to!ubyte(16);
        b = v[5 .. 7].to!ubyte(16);
    }

    this(ubyte r, ubyte g, ubyte b) @safe
    {
        this.r = r;
        this.g = g;
        this.b = b;
    }

    void set(ubyte r, ubyte g, ubyte b)
    {
        this.r = r;
        this.g = g;
        this.b = b;
    }

    string toString() const @safe
    {
        return "#%02x%02x%02x".format(r, g, b);
    }

    void add(Color p)
    {
        this.r = addBytes(this.r, p.r);
        this.g = addBytes(this.g, p.g);
        this.b = addBytes(this.b, p.b);
    }

    auto factor(float f)
    {
        return Color((this.r * f).to!ubyte, (this.g * f).to!ubyte, (this.b * f).to!ubyte);
    }
}

ubyte addBytes(ubyte b1, ubyte b2)
{
    auto h = b1 + b2;
    if (h > 255)
    {
        return 255;
    }
    return cast(ubyte) h;
}
