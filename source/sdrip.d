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
import std.datetime;
import vibe.data.json;

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

struct MinMaxWithDefault(T)
{
    T value;
    T defaultValue;
    T min;
    T max;
}

static minMaxWithDefault(T)(T v, T min, T max)
{
    return MinMaxWithDefault!(T)(v, v, min, max);
}

static minMaxWithDefault(T)(T v, T defaultValue, T min, T max)
{
    return MinMaxWithDefault!(T)(v, defaultValue, min, max);
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
    to.send(thisTid, Request(parameters));
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
    public abstract Json toJson() const @safe;
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

    override Json toJson() const
    {
        // dfmt off
        return Json(
                    ["name" : Json(key),
                     "type" : Json("bool"),
                     "value" : Json(value.value),
                     "defaultValue" : Json(value.defaultValue)]);
        // dfmt on
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

    override Json toJson() const
    {
        // dfmt off
        return Json(
                    ["name" : Json(key),
                     "type" : Json("string"),
                     "value" : Json(value.value),
                     "defaultValue" : Json(value.defaultValue)]);
        // dfmt on
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

    override Json toJson() const
    {
        // dfmt off
        return Json(
                    ["name" : Json(key),
                     "type" : Json("color"),
                     "value" : Json(color.value.to!string),
                     "defaultValue" : Json(color.defaultValue.to!string)]);
        // dfmt on
    }
}

class FloatProperty : Property
{
    MinMaxWithDefault!float value;
    this(string key, MinMaxWithDefault!float value)
    {
        super(key);
        this.value = value;
    }

    override immutable string toHtml()
    {
        return "%1$s %4$s <input type=\"text\" name=\"%1$s\" value=\"%2$s\" defaultValue=\"%3$s\" />%5$s".format(key,
                value.value, value.defaultValue, value.min, value.max);
    }

    override Json toJson() const
    {
        // dfmt off
        return Json(
                    ["name" : Json(key),
                     "type" : Json("float"),
                     "value" : Json(value.value),
                     "defaultValue" : Json(value.defaultValue)]);
        // dfmt on
    }
}

class DurationProperty : Property
{
    MinMaxWithDefault!Duration duration;

    this(string key, MinMaxWithDefault!Duration duration)
    {
        super(key);
        this.duration = duration;
    }

    override immutable string toHtml()
    {
        return "%1$s %3$s<input type=\"text\" name=\"%1$s\" value=\"%2$s\" defaultValue=\"%3$s\" />%4$s".format(key,
                duration.value.total!"seconds",
                duration.defaultValue.total!"seconds",
                duration.min.total!"seconds", duration.max.total!"seconds");
    }

    override Json toJson() const
    {
        return Json("nyi");
    }
}

class TimeOfDayProperty : Property
{
    WithDefault!TimeOfDay timeOfDay;
    this(string key, WithDefault!TimeOfDay timeOfDay)
    {
        super(key);
        this.timeOfDay = timeOfDay;
    }

    override immutable string toHtml()
    {
        return "%1$s <input type=\"time\" step=\"1\" name=\"%1$s\" value=\"%2$s\" defaultValue=\"%3$s\" />".format(key, // 1
                timeOfDay.value.toISOExtString(), // 2
                timeOfDay.defaultValue.toISOExtString() // 3
                );
    }

    override Json toJson() const
    {
        return Json("nyi");
    }
}
