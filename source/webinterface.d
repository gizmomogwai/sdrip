module webinterface;

import std.concurrency;
import std.experimental.logger;
import messages;
import vibe.vibe;

class WebInterface {
    Tid renderer;
    this(Tid renderer)
    {
        this.renderer = renderer;
    }

    void get()
    {
        try
        {
            auto status = renderer.sendReceive!GetState;
            auto current = status["current"].to!string;
            auto renderers = status["renderers"];
            import std.stdio;
            writeln(current);
            foreach (r; renderers) {
                writeln("renderer: ", r);
            }
            render!("index.dt", current, renderers);
        }
        catch (Exception e)
        {
            error(e);
        }
    }
    void getStatus()
    {
        import packageversion;
        import std.algorithm;
        import std.stdio;
        auto packages = packageversion.getPackages.sort!("a.name < b. name");
        render!("status.dt", packages);
    }
}
