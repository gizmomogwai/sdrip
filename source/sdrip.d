module sdrip;

import dotstar;
import find;
import std.concurrency;
import std.experimental.logger;
import messages;
import std.stdio;
import std.string;
import std.range;

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
    Renderer[] generators;
    Renderer current;
    this(Tid renderer, Renderer[] generators)
    {
        this.renderer = renderer;
        this.generators = generators;
        activate(generators[0].name);
    }

    void activate(string name)
    {

        if (current !is null)
        {
            current.renderer.send(thisTid, Shutdown());
            current = null;
        }

        current = generators.findBy!(a => a.name)(name).front;
        renderer.send(SetGenerator(), current.start());
    }

    public void shutdown()
    {
        if (current !is null)
        {
            current.renderer.shutdownAndWait();
        }
        renderer.shutdownAndWait();
    }
}

class Renderer
{
    immutable string name;
    immutable uint nrOfLeds;
    Tid renderer;

    this(string name, uint nrOfLeds)
    {
        this.name = name;
        this.nrOfLeds = nrOfLeds;
    }

    public final Tid start()
    {
        renderer = internalStart();
        return renderer;
    }

    protected abstract Tid internalStart();

    public immutable(Property)[] properties()
    {
        info("props");
        auto res = renderer.sendReceive!(GetProperties);
        return res;
    }

    bool apply(immutable(string)[] path, string value)
    {
        info("apply");
        return renderer.sendReceive!(SetProperties)(path, value);
    }
}

import std.traits : Fields;

auto sendReceive(Request)(Tid to, Fields!Request parameters)
{
    to.send(thisTid, Request(parameters));
    return (receiveOnly!(Request.Result)).result;
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
        const checked = `checked="checked"`;
        return `<table class="radio" name="%1$s"><tr><td colspan="2">%1$s</td></tr>`.format(key) ~ `<tr><td>true</td><td><label class="radio"><input type="radio" name="%s" value="true" defaultvalue="%s" %s/></label></td></tr>`
            .format(key, value.defaultValue, value.value ? checked : "") ~ `<tr><td>false</td><td><label class="radio"><input type="radio" name="%s" value="false" defaultvalue="%s" %s/></label></td></tr>`
            .format(key, value.defaultValue, value.value ? "" : checked) ~ `</table>`;
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
