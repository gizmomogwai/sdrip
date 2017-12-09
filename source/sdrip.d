/++
 + Profiles and properties
 +/
module sdrip;

import dotstar;
import find;
import std.concurrency;
import std.experimental.logger;
import messages;
import std.stdio;
import std.string;
import std.range;
import renderer;

struct WithDefault(T)
{
    T value;
    T defaultValue;
}

static withDefault(T)(T v)
{
    return WithDefault!(T)(v, v);
}

static withDefault(T)(T value, T defaultValue)
{
    return WithDefault!(T)(value, defaultValue);
}

class Profiles
{
    Tid renderer;
    bool shutdownSent = false;
    Renderer[] renderers;
    Renderer current;

    this(Tid renderer, Renderer[] renderers)
    {
        this.renderer = renderer;
        this.renderers = renderers;
        activate(renderers[0].name);
    }

    void activate(string name)
    {
        clearCurrent();

        current = renderers.findBy!(a => a.name)(name).front;
        renderer.send(SetRenderer(), current.start(), name);
    }

    public void shutdown()
    {
        clearCurrent();

        if (!shutdownSent)
        {
            renderer.shutdownAndWait();
            shutdownSent = true;
        }
    }

    private void clearCurrent()
    {
        if (current !is null)
        {

            current.renderer.shutdownAndWait();
            current = null;
        }
    }
}

import std.traits : Fields;

auto sendReceive(Request)(Tid to, Fields!Request parameters)
{
    to.send(thisTid, Request(parameters));
    Request.Result res;
    receive((Request.Result r) { res = r; });
    return res.result;
}

auto prioritySendReceive(Request)(Tid to, Fields!Request parameters)
{
    to.prioritySend(thisTid, Request(parameters));
    Request.Result res;
    receive((Request.Result r) { res = r; });
    return res.result;
}

class Property
{
    string key;
    this(string key) @safe
    {
        this.key = key;
    }

    public abstract immutable string toHtml();
}

class BoolProperty : Property
{
    WithDefault!bool value;
    this(string key, WithDefault!bool value)
    {
        super(key);
        this.value = value;
    }

    override immutable string toHtml()
    {
        return `<input type="checkbox" name="%1$s" %2$s data-toggle="toggle" onChange="this.form.submit();">%1$s</input>`
            .format(key, value.value ? "checked" : "")
            ~ `<input type="hidden" name="%1$s" value="off" />`.format(key);
    }
}

class StringProperty : Property
{
    WithDefault!string value;
    this(string key, WithDefault!string value)
    {
        super(key);
        this.value = value;
    }

    override immutable string toHtml()
    {
        return `%1$s <input type="text" name="%1$s" value="%2$s" defaultvalue="%3$s" />`.format(key,
                value.value, value.defaultValue);
    }
}

class ColorProperty : Property
{
    WithDefault!Color color;
    this(string key, WithDefault!Color color)
    {
        super(key);
        this.color = color;
    }

    override immutable string toHtml()
    {
        return `%1$s <input type="color" name="%1$s" value="%2$s" defaultValue="%3$s" />`.format(key,
                color.value, color.defaultValue);
    }

}
