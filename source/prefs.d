module prefs;

class Prefs {
    string[string] data;
    string get(string key, string defaultValue="") immutable
    {
        if (key in data) {
            return data[key];
        }
        return defaultValue;
    }
    auto add(string key, string value) {
        data[key] = value;
        return this;
    }
}

immutable(Prefs) load(T...)(T files) {
    import dyaml;
    Prefs res = new Prefs;
    foreach (file; files) {
        import std.file;
        import std.experimental.logger;
        import std.string;
        info("loading '%s'".format(file));
        if (!file.exists) {
            warning("file '%s' does not exist".format(file));
            continue;
        }
        auto data = new Loader(file).load();
        foreach (string key, string value; data) {
            res.add(key, value);
        }
    }
    return cast(immutable(Prefs)) res;
}
