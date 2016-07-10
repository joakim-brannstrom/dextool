/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.data.symbol.container;

import logger = std.experimental.logger;

//TODO move TypeKind to .data
import cpptooling.analyzer.type : TypeKind;

import cpptooling.data.representation : CppClass;
import cpptooling.data.symbol.typesymbol;
import cpptooling.data.symbol.types;

version (unittest) {
    import unit_threaded : Name;
    import unit_threaded : shouldEqual;
} else {
    struct Name {
        string name_;
    }
}

/* The design is such that the memory location of a stored value do not
 * change after storage.
 * Therefor storing both the ptr and a fast lookup into the stored
 * instances.
 *
 * TODO change to using the experimental allocators instead of the GC.
 * TODO Probably ensure that K is an integer to lower the memory pressure.
 * TODO bad name, change to something else more telling. Ok for now because the
 * type isn't exposed.
 */
private struct FastLookup(T, K) {
    T*[] instances;
    T*[K] lookup;

    invariant() {
        assert(instances.length == lookup.length);
    }

    /** The instance and corresponding key must be unique.
     *
     * The callers responsiblity to ensure uniqueness.  If broken, assert.
     */
    ref T put(T instance, in K key)
    in {
        assert((key in lookup) is null);
    }
    body {
        auto heap = new T(instance);
        instances ~= heap;
        lookup[key] = heap;

        return *heap;
    }

    auto find(in K key) const {
        import std.range : only, dropOne;
        import std.typecons : NullableRef;

        auto item = key in lookup;
        if (item is null) {
            return only(NullableRef!(const(T))(null)).dropOne;
        }

        return only(NullableRef!(const(T))(*item));
    }

    auto opSlice() @safe pure nothrow {
        import std.algorithm : map;

        return instances.map!(a => *a);
    }

    auto opSlice() @safe pure nothrow const {
        import std.algorithm : map;

        return instances.map!(a => *a);
    }
}

/** Contain symbols found during analyze.
 */
struct Container {
    private {
        FastLookup!(CppClass, FullyQualifiedNameType) classes;
        FastLookup!(TypeKind, USRType) types;
    }

    auto find(T)(USRType usr) const if (is(T == TypeKind))
    out (result) {
        logger.tracef("Find %susr:%s", result.length == 0 ? "failed, " : "", cast(string) usr);
    }
    body {
        return types.find(usr);
    }

    auto find(T)(FullyQualifiedNameType fqn) if (is(T == CppClass))
    out (result) {
        logger.tracef(result.length == 0, "No symbol found for '%s'", cast(string) fqn);
    }
    body {
        return classes.find(fqn);
    }

    string toString() const {
        import std.algorithm : joiner, map;
        import std.ascii : newline;
        import std.conv : to, text;
        import std.format : format;
        import std.range : only, chain;
        import cpptooling.analyzer.type;
        import cpptooling.data.type : LocationTag;

        // dfmt off
        return chain(
                     only("Container {\n").joiner,
                     only("classes {\n").joiner,
                        classes[].map!(a => "  " ~ a.fullyQualifiedName ~ newline).joiner,
                     only("} // classes\n").joiner,
                     only("types {\n").joiner,
                        types[].map!(a => format("  %s %s -> %s %s\n", a.info.kind.to!string(), cast(string) a.usr, a.internalGetFmt, a.loc.kind == LocationTag.Kind.loc ? a.loc.file : "noloc")).joiner,
                     only("} // types\n").joiner,
                     only("} //Container").joiner,
                    ).text;
        // dfmt on
    }

    void put(TypeKind value)
    in {
        assert(value.usr.length > 0);
    }
    body {
        if (value.usr in types.lookup) {
            return;
        }

        auto latest = types.put(value, value.usr);

        debug {
            import std.conv : to;
            import cpptooling.analyzer.type;
            import cpptooling.data.type : LocationTag, Location;

            logger.tracef("Stored kind:%s usr:%s repr:%s loc:%s", latest.info.kind.to!string,
                    cast(string) latest.usr, latest.toStringDecl(TypeAttr.init, "x"),
                    latest.loc.kind == LocationTag.Kind.loc ? latest.loc.file : "noloc");
        }
    }

    void put(T)(ref T cl, FullyQualifiedNameType fqn) if (is(T : CppClass)) {
        if (fqn in classes.lookup) {
            return;
        }

        classes.put(cl, fqn);
    }
}

@Name("should be able to use the found class")
unittest {
    import cpptooling.data.representation : CppClass, CppClassName;

    auto c = CppClass(CppClassName("Class"));

    Container cont;
    cont.put(c, c.fullyQualifiedName);

    // not really needed test but independent at two places, see the invariant.
    1.shouldEqual(cont.classes[].length);

    // should be able to find a stored class by the FQN
    auto found_class = cont.find!CppClass(FullyQualifiedNameType("Class")).front;

    // should be able to use the found class
    "Class".shouldEqual(found_class.name);
}

@Name("should list all contained classes")
unittest {
    import cpptooling.data.representation : CppClass, CppClassName;
    import test.helpers;
    import std.conv : to;

    Container cont;

    for (auto i = 0; i < 3; ++i) {
        auto c = CppClass(CppClassName("Class" ~ to!string(i)));
        cont.put(c, c.fullyQualifiedName);
    }

    cont.toString.shouldEqualPretty("Container {
classes {
  Class0
  Class1
  Class2
} // classes
types {
} // types
} //Container");
}

@Name("Should never be duplicates of content")
unittest {
    import cpptooling.data.representation : CppClass, CppClassName;
    import test.helpers;

    Container cont;

    for (auto i = 0; i < 3; ++i) {
        auto c = CppClass(CppClassName("Class"));
        cont.put(c, c.fullyQualifiedName);
    }

    cont.toString.shouldEqualPretty("Container {
classes {
  Class
} // classes
types {
} // types
} //Container");
}
