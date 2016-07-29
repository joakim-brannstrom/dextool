/*
 * Copied from phobos.
 * Remove when upgrading minimum compiler requirement to 2.071+
 *
 * Copyright: Copyright Digital Mars 2005 - 2009.
 * License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   $(WEB digitalmars.com, Walter Bright),
 *            Tomasz Stachowiak ($(D isExpressions)),
 *            $(WEB erdani.org, Andrei Alexandrescu),
 *            Shin Fujishiro,
 *            $(WEB octarineparrot.com, Robert Clipsham),
 *            $(WEB klickverbot.at, David Nadlinger),
 *            Kenji Hara,
 *            Shoichi Kato
 * Source:    $(PHOBOSSRC std/_traits.d)
 */
module cpptooling.utility.unqual;

/**
Removes all qualifiers, if any, from type $(D T).
 */
template Unqual(T) {
    version (none) // Error: recursive alias declaration @@@BUG1308@@@
    {
        static if (is(T U == const U))
            alias Unqual = Unqual!U;
        else static if (is(T U == immutable U))
            alias Unqual = Unqual!U;
        else static if (is(T U == inout U))
            alias Unqual = Unqual!U;
        else static if (is(T U == shared U))
            alias Unqual = Unqual!U;
        else
            alias Unqual = T;
    } else // workaround
    {
        static if (is(T U == immutable U))
            alias Unqual = U;
        else static if (is(T U == shared inout const U))
            alias Unqual = U;
        else static if (is(T U == shared inout U))
            alias Unqual = U;
        else static if (is(T U == shared const U))
            alias Unqual = U;
        else static if (is(T U == shared U))
            alias Unqual = U;
        else static if (is(T U == inout const U))
            alias Unqual = U;
        else static if (is(T U == inout U))
            alias Unqual = U;
        else static if (is(T U == const U))
            alias Unqual = U;
        else
            alias Unqual = T;
    }
}
