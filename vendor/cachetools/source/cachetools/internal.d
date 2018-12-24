module cachetools.internal;

private import std.typecons;
private import std.traits;

template StoredType(T) {
    static if (is(T == immutable) || is(T == const)) {
        static if (is(T == class)) {
            alias StoredType = Rebindable!T;
        } else {
            alias StoredType = Unqual!T;
        }
    } else {
        alias StoredType = T;
    }
}

import std.experimental.logger;

debug (cachetools) @safe @nogc nothrow {
    void safe_tracef(A...)(string f, scope A args) @safe @nogc nothrow {
        debug (cachetools)
            try {
                () @trusted @nogc { tracef(f, args); }();
            } catch (Exception e) {
            }
    }
}
