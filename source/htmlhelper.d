module htmlhelper;

import vibe.data.json;
import std.string;
import std.conv;

string renderBoolField(S, T)(S name, T value)
{
    string nameString = name.to!string;
    bool valueBool = value.to!bool;
    return `<input type="checkbox" name="%s" %s data-toggle="toggle" onChange="this.form.submit()" />`.format(
            nameString, valueBool ? "checked"
            : "") ~ `<input type="hidden" name="%s" value="off" />`.format(nameString);
}

string htmlForBoolProperty(Json p)
{
    return renderBoolField(p["name"], p["value"]);
}

string htmlForColorProperty(Json p)
{
    string name = p["name"].to!string;
    string color = p["value"].to!string;
    string defaultColor = p["defaultValue"].to!string;
    // dfmt off
    return `%1$s <input type="color" name="%1$s" value="%2$s" defaultValue="%3$s" />`
        .format(name, color, defaultColor);
    // dfmt on
}

string htmlForFloatProperty(Json p)
{
    string name = p["name"].to!string;
    string value = p["value"].to!string;
    string defaultValue = p["defaultValue"].to!string;
    /*
    string minValue = p["min"].to!string;
    string maxValue = p["max"].to!string;
    */
    return `%1$s <input type="text" name="%1$s" value="%2$s" defaultValue="%3$s" />`.format(name, value, defaultValue);
}

string renderProperty(Json p)
{
    switch (p["type"].to!string)
    {
    case "boolean":
        return htmlForBoolProperty(p);
    case "color":
        return htmlForColorProperty(p);
    case "float":
        return htmlForFloatProperty(p);
    default:
        return "nyi";
    }

}
