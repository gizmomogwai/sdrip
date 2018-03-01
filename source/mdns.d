module mdns;

import prefs;

auto announceServer(immutable(Prefs) settings)
{
    import std.process;
    import std.string;

    version (linux)
    {
        auto command = "avahi-publish-service -s %s _dotstar._tcp %s";
    }
    version (OSX)
    {
        auto command = "dns-sd -R %s _dotstar._tcp local %s";
    }
    return spawnShell(command.format(settings.get("location"), settings.get("port")));
}
