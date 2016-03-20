// Written in the D programming language.
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

@safe struct Container {
    invariant() {
        assert(cppclass.length == t_cppclass.length);
    }

    private {
        //TODO change to using a hash map
        CppClass*[] cppclass;
        TypeSymbol!(CppClass*)[] t_cppclass;
    }

    auto rangeTypeClass() @nogc {
        import cpptooling.utility.range : arrayRange;

        return arrayRange(t_cppclass);
    }

    /** Duplicate and store the class in the container.
     *
     * Only store classes that are fully analyzed.
     * Changes to parameter cl after storages are NOT reflected in the stored class.
     */
    void put(ref CppClass cl, FullyQualifiedNameType fqn) {
        //TODO change to using a hash map
        if (internalFind!CppClass(fqn).length != 0) {
            return;
        }

        auto heap_c = new CppClass(cl);
        cppclass ~= heap_c;
        t_cppclass ~= TypeSymbol!(CppClass*)(heap_c, fqn);
    }

    import std.typecons : NullableRef;

    // Do not spam log traces because of internal searches via put.
    // For further info see the public find
    private auto internalFind(T)(FullyQualifiedNameType fqn) {
        import std.string : toLower;
        import std.range : only, dropOne;
        import std.typecons : NullableRef;

        enum type_lower = "t_" ~ toLower(T.stringof);
        auto t_objs = __traits(getMember, typeof(this), type_lower);

        foreach (item; t_objs) {
            if (item.fullyQualifiedName == fqn) {
                return only(NullableRef!T(item.get));
            }
        }

        // When this happens the AST isn't complete.
        // Happens for example when trying to create a mock of std::system_error

        // The only sensible option left is to return a zero length range
        // to still allow range iterators etc to work.
        return only(NullableRef!T((T*).init)).dropOne;
    }

    /** Find the represented object via search parameter.
     *
     * TODO Decouple the compile time arg from the concrete type by basing it
     * on for example an enum. By doing so it removes the dependency of all
     * callers having to specify the type, and knowing the type.
     *
     * Return: ref to object or null
     */
    auto find(T)(FullyQualifiedNameType fqn) {
        logger.trace("searching for: ", cast(string) fqn);

        auto rval = internalFind!T(fqn);

        logger.errorf(rval.length == 0,
                "AST is not complete. No symbol found for '%s'", cast(string) fqn);

        return rval;
    }

    string toString() const {
        import std.algorithm : joiner, map;
        import std.ascii : newline;
        import std.conv : text;
        import std.range : only, chain, takeOne;

        // dfmt off
        return chain(
                     only("Container {" ~ newline).joiner(),
                     t_cppclass.takeOne.map!(a => "classes {" ~ newline).joiner,
                     chain(
                           t_cppclass.map!(a => "  " ~ a.fullyQualifiedName ~ newline),
                          ).joiner(),
                     t_cppclass.takeOne.map!(a => "} // classes" ~ newline).joiner,
                     only("} //Container").joiner(),
                    ).text;
        // dfmt on
    }
}

@Name("should be able to use the found class")
unittest {
    import cpptooling.data.representation : CppClass, CppClassName;

    auto c = CppClass(CppClassName("Class"));

    Container cont;
    cont.put(c, c.fullyQualifiedName);

    // not really needed test but independent at two places, see the invariant.
    1.shouldEqual(cont.cppclass.length);

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
} //Container");
}
