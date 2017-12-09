/// http interface
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
            auto index = theRenderer.sendReceive!Index;
            auto name = index.current;
            auto renderer = index.renderer;
            auto active = removeTitle(theRenderer.sendReceive!(GetProperties)(Prefix())[0]);

            render!("index.dt", name, renderer, active);
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

    private auto filterDoubleKeys(HTTPServerRequest request)
    {
        string[string] res;
        foreach (k, v; request.form)
        {
            if (k !in res)
            {
                res[k] = v;
            }
        }
        return res;
    }

    private void setProperties(HTTPServerRequest request) {
        foreach (k, v; filterDoubleKeys(request))
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
    }

    void postSet(HTTPServerRequest request)
    {
        info("WebInterface:postSet", request.form);
        setProperties(request);
        renderCurrent();
    }

    void postActivate(HTTPServerRequest request)
    {
        info("WebInterface:postSet", request.form);
        setProperties(request);
        get();
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

    private auto removeTitle(immutable Property p) {
        import std.regex;
        auto r = regex(">.*</input>", "g");
        return replaceAll(p.toHtml(), r, "/>");
    }

    void renderCurrent()
    {
        import vibe.vibe;

        try
        {
            auto name = theRenderer.prioritySendReceive!GetCurrent;
            auto properties = theRenderer.prioritySendReceive!(GetProperties)(Prefix());
            auto active = removeTitle(properties[0]);

            render!("current.dt", name, properties, active);
        }
        catch (Throwable t)
        {
            import std.stdio;

            writeln(t);
        }
    }
}
