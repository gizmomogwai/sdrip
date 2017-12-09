/// findby
module find;

InputRange findBy(alias pred = "a", InputRange, Element)(InputRange haystack, scope Element needle)
{
    import std.functional;

    alias transform = unaryFun!pred;
    foreach (i, ref e; haystack)
    {
        if (transform(e) == needle)
        {
            return haystack[i .. $];
        }
    }
    return haystack[$ .. $];
}
