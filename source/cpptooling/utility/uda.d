/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Backport from DMD-FE 2.072.0
*/
module cpptooling.utility.uda;

/++
    Gets the matching $(DDSUBLINK spec/attribute, uda, user-defined attributes)
    from the given symbol.

    If the UDA is a type, then any UDAs of the same type on the symbol will
    match. If the UDA is a template for a type, then any UDA which is an
    instantiation of that template will match. And if the UDA is a value,
    then any UDAs on the symbol which are equal to that value will match.

    See_Also:
        $(LREF hasUDA)
  +/
template getUDAs(alias symbol, alias attribute) {
    import std.meta : Filter;

    template isDesiredUDA(alias toCheck) {
        static if (is(typeof(attribute)) && !__traits(isTemplate, attribute)) {
            static if (__traits(compiles, toCheck == attribute))
                enum isDesiredUDA = toCheck == attribute;
            else
                enum isDesiredUDA = false;
        } else static if (is(typeof(toCheck))) {
            static if (__traits(isTemplate, attribute))
                enum isDesiredUDA = isInstanceOf!(attribute, typeof(toCheck));
            else
                enum isDesiredUDA = is(typeof(toCheck) == attribute);
        } else static if (__traits(isTemplate, attribute))
            enum isDesiredUDA = isInstanceOf!(attribute, toCheck);
        else
            enum isDesiredUDA = is(toCheck == attribute);
    }

    alias getUDAs = Filter!(isDesiredUDA, __traits(getAttributes, symbol));
}
