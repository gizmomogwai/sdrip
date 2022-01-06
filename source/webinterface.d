module webinterface;

import std.concurrency;
import std.experimental.logger;
import messages;

import vibe.vibe;

class WebInterface
{
    Tid renderer;
    this(Tid renderer)
    {
        this.renderer = renderer;
    }

    public void postActivate(HTTPServerRequest request)
    {
        info("WebInterface:postActivate ", request.form);
        renderer.sendReceive!Activate(request.form["name"]);
        renderCurrent();
    }

    public void get()
    {
        renderAll();
    }

    public void getCurrent()
    {
        renderCurrent();
    }

    public void postToggle(HTTPServerRequest request)
    {
        info("WebInterface:postToggle ", request.form);
        renderer.sendReceive!Toggle;
        get();
    }

    private auto filterDoubleKeys(HTTPServerRequest request)
    {
        string[string] res;
        foreach (k, v; request.form.byKeyValue)
        {
            if (k !in res)
            {
                res[k] = v;
            }
        }
        return res;
    }

    public void postSet(HTTPServerRequest request)
    {
        info(request.form);
        info(request);
        foreach (k, v; filterDoubleKeys(request))
        {
            renderer.sendReceive!Apply(k, v);
        }
        renderCurrent();
    }

    public void getStatus()
    {
        import packageversion;
        import std.algorithm;

        auto packages = packageversion.getPackages.sort!("a.name < b. name");
        render!("status.dt", packages);
    }

    void renderAll()
    {
        auto status = renderer.sendReceive!GetState;
        auto current = status["current"];
        auto renderers = status["renderers"];
        render!("index.dt", current, renderers);
    }

    void renderCurrent()
    {
        info("getstate");
        auto status = renderer.sendReceive!GetState;
        auto currentName = status["current"]["name"].to!string;
        info("currentName ", currentName);
        auto renderers = status["renderers"];
        import std.stdio;

        foreach (current; renderers)
        {
            writeln(current);
            if (current["name"].to!string == currentName)
            {
                renderCurrent(current);
                return;
            }
        }
        warning("Cannot find %s", currentName);
    }

    private void renderCurrent(Json current)
    {
        render!("current.dt", current);
    }

}
