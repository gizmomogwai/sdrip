/++
 + Lowlevel api to work with a dotstar strip.
 +/
module dotstar;

import core.thread;
import prefs;
import std.conv;
import std.experimental.logger;
import std.math;
import std.socket;
import std.string;

abstract class Strip
{
    /// ARGB
    ubyte[] ledBuffer;
    this(uint nrOfLeds)
    {
        this.ledBuffer = new ubyte[nrOfLeds * 4];
    }

    ~this()
    {
    }

    Strip set(uint idx, Color p)
    {
        return set(idx, p.a, p.r, p.g, p.b);
    }

    Strip set(uint idx, ubyte a, ubyte r, ubyte g, ubyte b)
    {
        auto i = idx * 4;
        import std.stdio;

        ledBuffer[i] = cast(ubyte)(0b11100000 | (a >> 3));
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
            set(i, Color(255, 255, 0, 0));
        }
        refresh();
        Thread.sleep(dur!("seconds")(1));
        for (int i = 0; i < size(); ++i)
        {
            set(i, Color(255, 0, 255, 0));
        }
        refresh();
        Thread.sleep(dur!("seconds")(1));
        for (int i = 0; i < size(); ++i)
        {
            set(i, Color(255, 0, 0, 255));
        }
        refresh();
        Thread.sleep(dur!("seconds")(1));
    }

    abstract Strip refresh();
}

version (linux)
{
    /+
     + References:
     + - https://www.kernel.org/doc/Documentation/spi/spidev
     + - https://cdn-shop.adafruit.com/datasheets/APA102.pdf
     + - https://github.com/adafruit/Adafruit_DotStar_Pi/blob/master/dotstar.c
     + - https://cpldcpu.wordpress.com/2014/11/30/understanding-the-apa102-superled/
     +/
    class Spi
    {
        struct IocTransfer
        {
            ulong txBuffer;
            ulong rxBuffer;
            uint length;
            uint speedInHz;
            ushort delayInUSeconds;
            ubyte bitsPerWord;
            ubyte csChange;
            ubyte txNBits;
            ubyte rxNBits;
            ubyte wordDelayInUSeconds;
            ubyte padding;
        }

        enum SPI_IOC_MAGIC = 'k';
        enum SPI_MODE_0 = 0;
        enum SPI_NO_CS = 0x40;
        enum SPI_IOC_WR_MODE = _IOW!(ubyte)(SPI_IOC_MAGIC, 1);
        enum BITRATE = 8_000_000;
        enum SPI_IOC_WR_MAX_SPEED_HZ = _IOW!(uint)(SPI_IOC_MAGIC, 4);

        import core.sys.posix.sys.ioctl;
        import std.stdio;

        std.stdio.File file;
        IocTransfer[3] transfer = [
            {speedInHz: BITRATE, bitsPerWord: 8,},
            {speedInHz: BITRATE, bitsPerWord: 8,},
            {speedInHz: BITRATE, bitsPerWord: 8,},
        ];

        this()
        {
            file.open("/dev/spidev0.0", "wb");

            ubyte mode = SPI_MODE_0 | SPI_NO_CS;
            int res = ioctl(file.fileno, SPI_IOC_WR_MODE, &mode);
            if (res != 0)
            {
                throw new Exception("Cannot do ioctl to set spi write mode");
            }

            // TODO can be removed?
            res = ioctl(file.fileno, SPI_IOC_WR_MAX_SPEED_HZ, BITRATE);
        }

        ~this()
        {
            file.close;
        }

        void write(ubyte[] data)
        {
            int nrOfPixels = cast(int)(data.length / 4);

            // TODO can be removed?
            transfer[0].speedInHz = BITRATE;
            transfer[1].speedInHz = BITRATE;
            transfer[2].speedInHz = BITRATE;
            //

            transfer[1].txBuffer = cast(ulong)(data.ptr);
            transfer[1].length = nrOfPixels * 4; // number of total bytes
            transfer[2].length = (nrOfPixels + 15) / 8 / 2; // half the number of pixels in bits for the endframe
            int res = ioctl(file.fileno, spi_ioc_message!3(), &transfer);
        }

        static auto spi_ioc_message(size_t n)()
        {
            return _IOW!(char[spi_msgsize(n)])(SPI_IOC_MAGIC, 0);
        }

        static size_t spi_msgsize(size_t n)
        {
            return ((n * (IocTransfer.sizeof)) < (1 << _IOC_SIZEBITS)) ? (n * (IocTransfer.sizeof))
                : 0;
        }
    }

    class SpiStrip : Strip
    {
        Spi spi;
        this(uint nrOfLeds)
        {
            super(nrOfLeds);
            this.spi = new Spi;
        }

        ~this()
        {
            this.spi = null;
        }

        override Strip refresh()
        {
            spi.write(ledBuffer);
            return this;
        }
    }
}

/+
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
    ~this() {
        stream.close();
    }
    override Strip refresh()
    {
        stream.write(ledBuffer);
        return this;
    }
}
+/

class DummyStrip : Strip
{
    this(uint nrOfLeds)
    {
        super(nrOfLeds);
    }

    ~this()
    {
    }

    override public Strip refresh()
    {
        return this;
    }
}

class TerminalStrip : Strip
{
    this(uint nrOfLeds)
    {
        super(nrOfLeds);
    }

    override public Strip refresh()
    {
        import colored;
        import std;

        write("\x1b[?25l"); // switch off cursor
        scope (exit)
        {
            write("\x1b[?25h"); // switch on cursor
        }
        foreach (pixel; ledBuffer.chunks(4))
        {
            auto h = cast(ubyte)((pixel[0] & 0b00011111) << 3);
            write(" ".onRgb(h, h, h));
        }
        writeln;
        foreach (pixel; ledBuffer.chunks(4))
        {
            write(" ".onRgb(pixel[3], pixel[2], pixel[1]));
        }
        writeln;
        write("\033[2A");
        return this;
    }
}

struct Color
{
    ubyte a;
    ubyte r;
    ubyte g;
    ubyte b;

    this(string v) @safe
    {
        switch (v.length)
        {
        case 9:
            {
                if (v[0 .. 1] != "#")
                {
                    throw new Exception(
                            "illegal color string format: '%s' expected #aarrggbb".format(v));
                }
                a = v[1 .. 3].to!ubyte(16);
                r = v[3 .. 5].to!ubyte(16);
                g = v[5 .. 7].to!ubyte(16);
                b = v[7 .. 9].to!ubyte(16);
                break;
            }
        case 7:
            {
                if (v[0 .. 1] != "#")
                {
                    throw new Exception(
                            "illegal color string format: '%s' expected #rrggbb".format(v));
                }
                a = 0xff;
                r = v[1 .. 3].to!ubyte(16);
                g = v[3 .. 5].to!ubyte(16);
                b = v[5 .. 7].to!ubyte(16);
                break;
            }
        default:
            throw new Exception(
                    "illegal color string format: '%s' expected #aarrggbb or #rrggbb".format(v));
        }
    }

    this(ubyte a, ubyte r, ubyte g, ubyte b) @safe
    {
        this.a = a;
        this.r = r;
        this.g = g;
        this.b = b;
    }

    /++
     + Params:
     +      h = hue 0f <= h < 360f
     +      s = saturation 0.0f <= s <= 1.0f
     +      v = value 0.0f <= v <= 1.0f
     +/
    static Color hsv(float h, float s = 1.0f, float v = 1.0f) @safe
    {
        import std.typecons;

        float c = s * v;
        float x = c * (1 - abs(((h / 60) % 2) - 1));
        float m = v - c;
        auto c_ = tuple!(float, "r", float, "g", float, "b");
        if (h >= 0 && h < 60)
        {
            c_.r = c;
            c_.g = x;
            c_.b = 0;
        }
        else if (h >= 60 && h < 120)
        {
            c_.r = x;
            c_.g = c;
            c_.b = 0;
        }
        else if (h >= 120 && h < 180)
        {
            c_.r = 0;
            c_.g = c;
            c_.b = x;
        }
        else if (h >= 180 && h < 240)
        {
            c_.r = 0;
            c_.g = x;
            c_.b = c;
        }
        else if (h >= 240 && h < 300)
        {
            c_.r = x;
            c_.g = 0;
            c_.b = c;
        }
        else
        {
            c_.r = c;
            c_.g = 0;
            c_.b = x;
        }
        return Color(255, ((c_.r + m) * 255).lround.to!ubyte, ((c_.g + m) * 255)
                .lround.to!ubyte, ((c_.b + m) * 255).lround.to!ubyte);
    }

    void set(ubyte a, ubyte r, ubyte g, ubyte b)
    {
        this.a = a;
        this.r = r;
        this.g = g;
        this.b = b;
    }

    string toString() const @safe
    {
        return "#%02x%02x%02x".format(r, g, b); // used for html -> not alpha possible
    }

    void add(Color p)
    {
        this.r = addBytes(this.r, p.r);
        this.g = addBytes(this.g, p.g);
        this.b = addBytes(this.b, p.b);
    }

    auto factor(float f)
    {
        return Color(this.a, (this.r * f).to!ubyte, (this.g * f).to!ubyte, (this.b * f).to!ubyte);
    }
}

@("hsv2rgb") unittest
{
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

    auto orange = Color.hsv(30);
    orange.r.shouldEqual(0xff);
    orange.g.shouldEqual(0x80);
    orange.b.shouldEqual(0x00);
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

Strip createStrip(immutable(Prefs) settings)
{
    auto nrOfLeds = settings.get("nr_of_leds").to!int;
    auto strip = settings.get("strip");
    trace(strip, ": ", nrOfLeds);
    switch (strip)
    {
        version (linux)
        {
    case "spi":
            return new SpiStrip(nrOfLeds);
        }
        /+    case "tcp":
        auto host = settings.get("host");
        info("tcpstrip: ", host);
        return new TcpStrip(nrOfLeds, host);
+/
    case "dummy":
        return new DummyStrip(nrOfLeds);
    case "terminal":
        return new TerminalStrip(nrOfLeds);
    case "":
    default:
        warning("dummystrip");
        return new DummyStrip(nrOfLeds);
    }
}
