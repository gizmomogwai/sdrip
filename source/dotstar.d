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
        return set(idx, p.a, p.r, p.g, p.b);
    }

    Strip set(uint idx, ubyte a, ubyte r, ubyte g, ubyte b)
    {
        auto i = idx * 4;
        ledBuffer[i] = a;
        ledBuffer[i + 1] = r;
        ledBuffer[i + 2] = g;
        ledBuffer[i + 3] = b;
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
        stream.write(ledBuffer);
        return this;
    }

    override void close()
    {
        stream.close();
    }
}

class DummyStrip : Strip
{
    this(uint nrOfLeds)
    {
        super(nrOfLeds);
    }

    override public Strip refresh()
    {
        info("refresh");
        return this;
    }

    override public void close()
    {
        info("close");
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

    /++
     + Params:
     +      h = hue 0 <= h < 360
     +      s = saturation 0.0f <= s <= 1.0f
     +      v = value 0.0f <= v <= 1.0f
     +/
    static Color hsv(int h, float s=1.0f, float v=1.0f) @safe {
        import std.typecons;
        import std.math;
        auto c = s * v;
        auto x = c * (1 - abs(((h / 60) % 2) - 1));
        auto m = v - c;
        auto c_ = tuple!(float, "r", float, "g", float, "b");
        if (h >= 0 && h < 60) {
            c_.r = c;
            c_.g = x;
            c_.b = 0;
        } else if (h >= 60 && h < 120) {
            c_.r = x;
            c_.g = c;
            c_.b = 0;
        } else if (h >= 120 && h < 180) {
            c_.r = 0;
            c_.g = c;
            c_.b = x;
        } else if (h >= 180 && h < 240) {
            c_.r = 0;
            c_.g = x;
            c_.b = c;
        } else if (h >= 240 && h < 300) {
            c_.r = x;
            c_.g = 0;
            c_.b = c;
        } else {
            c_.r = c;
            c_.g = 0;
            c_.b = x;
        }
        return Color(((c_.r + m) * 255).lround.to!ubyte,
                     ((c_.g + m) * 255).lround.to!ubyte,
                     ((c_.b + m) * 255).lround.to!ubyte
                     );
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

@("hsv2rgb") unittest {
    import unit_threaded;
    auto black = Color.hsv(0, 0, 0);
    black.r.shouldEqual(0x00);
    black.g.shouldEqual(0x00);
    black.b.shouldEqual(0x00);

    auto red = Color.hsv(0);
    red.r.shouldEqual(0xff);
    red.g.shouldEqual(0x00);
    red.b.shouldEqual(0x00);

    auto yellow = Color.hsv(60);
    yellow.r.shouldEqual(0xff);
    yellow.g.shouldEqual(0xff);
    yellow.b.shouldEqual(0x00);

    auto lime = Color.hsv(120);
    lime.r.shouldEqual(0x00);
    lime.g.shouldEqual(0xff);
    lime.b.shouldEqual(0x00);

    auto cyan = Color.hsv(180);
    cyan.r.shouldEqual(0x00);
    cyan.g.shouldEqual(0xff);
    cyan.b.shouldEqual(0xff);

    auto blue = Color.hsv(240);
    blue.r.shouldEqual(0x00);
    blue.g.shouldEqual(0x00);
    blue.b.shouldEqual(0xff);

    auto magenta = Color.hsv(300);
    magenta.r.shouldEqual(0xff);
    magenta.g.shouldEqual(0x00);
    magenta.b.shouldEqual(0xff);

    auto silver = Color.hsv(0, 0, .75f);
    silver.r.shouldEqual(0xbf);
    silver.g.shouldEqual(0xbf);
    silver.b.shouldEqual(0xbf);

    auto gray = Color.hsv(0, 0, .5f);
    gray.r.shouldEqual(0x80);
    gray.g.shouldEqual(0x80);
    gray.b.shouldEqual(0x80);

    auto maroon = Color.hsv(0, 1.0f, .5f);
    maroon.r.shouldEqual(0x80);
    maroon.g.shouldEqual(0x00);
    maroon.b.shouldEqual(0x00);

    auto olive = Color.hsv(60, 1.0f, .5f);
    olive.r.shouldEqual(0x80);
    olive.g.shouldEqual(0x80);
    olive.b.shouldEqual(0x00);

    auto green = Color.hsv(120, 1.0f, .5f);
    green.r.shouldEqual(0x00);
    green.g.shouldEqual(0x80);
    green.b.shouldEqual(0x00);

    auto teal = Color.hsv(180, 1.0f, .5f);
    teal.r.shouldEqual(0x00);
    teal.g.shouldEqual(0x80);
    teal.b.shouldEqual(0x80);

    auto navy = Color.hsv(240, 1.0f, .5f);
    navy.r.shouldEqual(0x00);
    navy.g.shouldEqual(0x00);
    navy.b.shouldEqual(0x80);

    auto purple = Color.hsv(300, 1.0f, .5f);
    purple.r.shouldEqual(0x80);
    purple.g.shouldEqual(0x00);
    purple.b.shouldEqual(0x80);
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
