/// created a strip
module stripfactory;

import prefs;
import dotstar;
import std.experimental.logger;

Strip createStrip(uint nrOfLeds, immutable(Prefs) settings)
{
    if (settings.get("dummystrip") != "")
    {
        return new DummyStrip(nrOfLeds);
    }
    if (settings.get("tcpstrip") != "")
    {
        auto host = settings.get("tcpstrip");
        info("tcpstrip: ", host);
        return new TcpStrip(nrOfLeds, host);
    }
    info("spistrip");
    return new SpiStrip(nrOfLeds);
}
