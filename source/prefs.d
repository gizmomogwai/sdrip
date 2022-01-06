/// Merged multi-file prefs
module prefs;

struct Prefs
{
    string[string] data;
    string get(string key, string defaultValue = "") immutable
    {
        if (key in data)
        {
            return data[key];
        }
        return defaultValue;
    }

    auto add(string key, string value)
    {
        data[key] = value;
        return this;
    }

    string toString() immutable
    {
        import std.string;

        return "%s".format(data);
    }
}

auto load(T...)(T files)
{
    import dyaml;

    Prefs res;
    foreach (file; files)
    {
        import std.file;
        import std.experimental.logger;
        import std.string;
        import std.path;

        auto h = file.absolutePath;
        info("loading '%s'".format(h));
        if (!file.exists)
        {
            warning("file '%s' does not exist".format(h));
            continue;
        }
        auto data = Loader.fromFile(h).load();
        foreach (string key, string value; data)
        {
            res = res.add(key, value);
        }
    }
    return cast(immutable) res;
}
