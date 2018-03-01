module state;

struct Parameter {
    string name;
    string type;
    string[string] keyValues;
}

struct Profile
{
    string name;
    Parameter[] parameters;
}

struct State {
    string currentProfile;
    Profile[] profiles;
}
