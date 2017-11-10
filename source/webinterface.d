module webinterface;

import sdrip;
import vibe.vibe;
import std.experimental.logger;

class WebInterface
{

    Profiles profiles;
    this(Profiles profiles)
    {
        this.profiles = profiles;
    }

    void get()
    {
        import vibe.vibe;

        info("WebInterface:get");
        render!("index.dt", profiles);
    }

    void getShutdown()
    {
        exitEventLoop();
    }

    void postSet(HTTPServerRequest request)
    {
        info("WebInterface:postSet");
        foreach (k, v; request.form)
        {
            trace(k, " -> ", v);
            if (profiles.current.apply(k.split(".").idup, v))
            {
                trace("set %s to %s OK".format(k, v));
            }
            else
            {
                trace("set %s to %s NOT OK".format(k, v));
            }
        }
        renderCurrent();
    }
    /*
      void getCurrent()
      {
      info("WebInterface:getCurrent");
      renderCurrent();
      }
    */
    void postActivate(string name)
    {
        info("WebInterface:postActivate ", name);
        profiles.activate(name);
        renderCurrent();
    }

    void renderCurrent()
    {
        import vibe.vibe;

        try
        {
            render!("current.dt", profiles);
        }
        catch (Throwable t)
        {
            import std.stdio;

            writeln(t);
        }
    }
}
