module webinterface;

import sdrip;
import vibe.vibe;
import std.experimental.logger;
import messages;

class WebInterface
{

    Tid theRenderer;
    this(Tid renderer)
    {
        this.theRenderer = renderer;
    }

    void get()
    {
        import vibe.vibe;
        error("-------------------------------------");
        try
        {
            trace("Index");
            auto index = theRenderer.sendReceive!Index;
            trace("Index");
            auto name = index.current;
            trace("Index");
            auto renderer = index.renderer;
            trace("Index");
            render!("index.dt", name, renderer);
        }
        catch (Exception e)
        {
            error(e);
        }
    }

    void postShutdown()
    {
        info("shutting down");
        theRenderer.shutdownAndWait();
        info("shutting down complete ... killing event loop");

        exitEventLoop();
    }

    void postSet(HTTPServerRequest request)
    {
        info("WebInterface:postSet");
        foreach (k, v; request.form)
        {
            trace(k, " -> ", v);
            auto result = theRenderer.sendReceive!Apply(k.split(".").idup, v);
            if (result)
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

    void getCurrent()
    {
        info("WebInterface:getCurrent");
        try
        {

            renderCurrent();
        }
        catch (Exception e)
        {
            error(e);
        }
    }

    void postActivate(string name)
    {
        info("WebInterface:postActivate ", name);
        theRenderer.sendReceive!Activate(name);
        renderCurrent();
    }

    void renderCurrent()
    {
        import vibe.vibe;

        try
        {
            auto name = theRenderer.sendReceive!GetCurrent;
            auto properties = theRenderer.sendReceive!(GetProperties)(Prefix());
            render!("current.dt", name, properties);
        }
        catch (Throwable t)
        {
            import std.stdio;

            writeln(t);
        }
    }
}
