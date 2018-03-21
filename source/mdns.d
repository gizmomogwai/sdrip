module mdns;

import prefs;
import std.string;

auto getPort(string bind) {
  auto idx = bind.lastIndexOf(":");
  return bind[idx+1..$];
}

@("getPortFromBind") unittest {
  import unit_threaded;
  getPort("0.0.0.0:10").shouldEqual("10");
}
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
    return spawnShell(command.format(settings.get("location"), settings.get("bind").getPort));
}
