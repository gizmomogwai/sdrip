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
    public void postActivate(HTTPServerRequest request)
    {
        info("WebInterface:postActivate ", request.form);
        renderer.sendReceive!Activate(request.form["name"]);
        renderCurrent();
    }
    public void get()
    {
        try
        {
            renderCurrent();
        }
        catch (Exception e)
        {
            error(e);
        }
    }
    public void postToggle(HTTPServerRequest request)
    {
        info("WebInterface:postToggle ", request.form);
        renderer.sendReceive!Toggle;
        get();
    }

    public void getStatus()
    {
        import packageversion;
        import std.algorithm;
        import std.stdio;
        auto packages = packageversion.getPackages.sort!("a.name < b. name");
        render!("status.dt", packages);
    }
    void renderCurrent()
    {
        auto status = renderer.sendReceive!GetState;
        auto current = status["current"];
        auto renderers = status["renderers"];
        render!("index.dt", current, renderers);
    }
}
