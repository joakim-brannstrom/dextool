// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.data.symbol.typesymbol;

import std.traits : isPointer;

import cpptooling.data.symbol.types;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import unit_threaded : Name;
    import unit_threaded : shouldEqual;
} else {
    struct Name {
        string name_;
    }
}

/** Wrap a pointer with metadata.
 *
 * The metadata is used to find the symbol in search algorithms.
 */
@safe struct TypeSymbol(T) if (isPointer!T) {
    private T target;
    FullyQualifiedNameType fullyQualifiedName;

    this(T target, FullyQualifiedNameType fqn)
    in {
        assert(target !is null);
    }
    body {
        this.target = target;
        this.fullyQualifiedName = fqn;

        import std.traits : hasMember, PointerTarget;

        static if (!hasMember!(Kind, PointerTarget!T.stringof)) {
            static assert(false,
                    "No member in cpptooling.data.symbol.types.Kind matching parameter "
                    ~ PointerTarget!T.stringof);
        }
    }

    bool opEquals(ref const this rhs) pure nothrow const {
        return fullyQualifiedName == rhs.fullyQualifiedName;
    }

    bool opEquals(FullyQualifiedNameType rhs) pure nothrow const {
        return fullyQualifiedName == rhs;
    }

    T get() {
        return target;
    }

    alias get this;
}

/** Wrap a pointer with metadata.
 *
 * The metadata is used to find the symbol in search algorithms.
 */
@safe struct TypeSymbol2(T) if (isPointer!T) {
    private T target;
    USRType usr;

    this(T target, USRType usr)
    in {
        assert(target !is null);
    }
    body {
        this.target = target;
        this.usr = usr;

        import std.traits : hasMember, PointerTarget;

        static if (!hasMember!(Kind, PointerTarget!T.stringof)) {
            static assert(false,
                    "No member in cpptooling.data.symbol.types.Kind matching parameter "
                    ~ PointerTarget!T.stringof);
        }
    }

    bool opEquals(ref const this rhs) pure nothrow const {
        return usr == rhs.usr;
    }

    bool opEquals(USRType rhs) pure nothrow const {
        return usr == rhs;
    }

    T get() {
        return target;
    }

    alias get this;
}

@Name("should be equal (simple)")
unittest {
    import cpptooling.data.representation : CppClass, CppClassName;

    auto c = CppClass(CppClassName("Class"));
    auto sym1 = TypeSymbol!(CppClass*)(&c, c.fullyQualifiedName);
    auto sym2 = TypeSymbol!(CppClass*)(&c, c.fullyQualifiedName);

    assert(sym1 == sym2);
    assert(sym1 == FullyQualifiedNameType("Class"));
}

@Name("should be able to access the wrapped type")
unittest {
    import cpptooling.data.representation : CppClass, CppClassName;

    auto c = CppClass(CppClassName("Class"));
    auto sym = TypeSymbol!(CppClass*)(&c, c.fullyQualifiedName);

    assert("Class" == sym.name);
}
