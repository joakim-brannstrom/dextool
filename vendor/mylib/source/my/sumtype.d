/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.sumtype;

public import sumtype;

/** Check if an instance of a sumtype contains the specific type.
 *
 * This is from the D forum by Paul Backus, the author of sumtype.
 *
 * Example:
 * ---
 * assert(someType.contains!int);
 * ---
 *
 */
bool contains(T, ST)(ST st) if (isSumType!ST) {
    return st.match!(value =>  is(typeof(value) == T));
}

@("shall match the sumtype")
unittest {
    alias T = SumType!(int, bool, char);
    auto a = T(true);
    assert(a.contains!bool);
    assert(!a.contains!int);
}

/** Restrict matching in a sumtype to a bundle of types.
 *
 */
template restrictTo(Args...) if (Args.length >= 1) {
    import std.meta : IndexOf = staticIndexOf;

    alias Types = Args[0 .. $ - 1];
    alias fun = Args[$ - 1];

    auto ref restrictTo(T)(auto ref T value) if (IndexOf!(T, Types) >= 0) {
        import core.lifetime : forward;

        static assert(IndexOf!(T, Types) >= 0);
        return fun(forward!value);
    }
}

@("shall restrict matching")
unittest {
    static struct Foo0 {
    }

    static struct Foo1 {
    }

    static struct Foo2 {
    }

    static struct Foo3 {
    }

    static struct Foo4 {
    }

    static struct Bar0 {
    }

    static struct Bar1 {
    }

    static struct Bar2 {
    }

    SumType!(Foo0, Foo1, Foo2, Foo3, Foo4, Bar0, Bar1, Bar2) someType;

    someType.match!(restrictTo!(Foo0, Foo1, Foo2, Foo3, val => {}),
            restrictTo!(Bar0, Bar1, Bar2, val => {}), _ => {});
}

/// For ignoring types.
void ignore(T)(T) {
}

// TODO: why doesn't this work?
//void ignore(T)(auto ref T) {}

@("shall ignore the type")
unittest {
    static struct A {
    }

    static struct B {
    }

    static struct C {
    }

    SumType!(A, B, C) obj;

    ignore(A.init);

    //You can instantiate it explicitly to ignore a specific type:
    obj.match!(ignore!A, (B b) {}, (C c) {});

    //// Or you can use it as a catch-all handler:
    obj.match!((A a) {}, ignore);
}

/** All return types from `Args`.
 */
template AllReturn(Args...) if (Args.length >= 1) {
    import std.meta : AliasSeq;
    import std.traits : ReturnType;

    static if (Args.length == 1) {
        alias AllReturn = ReturnType!(Args[0]);
    } else {
        alias AllReturn = AliasSeq!(ReturnType!(Args[0]), AllReturn!(Args[1 .. $]));
    }
}

alias SumTypeFromReturn(T...) = SumType!(AllReturn!T);

@("shall make a sumtype from the return types")
unittest {
    int fn1() {
        return 0;
    }

    double fn2() {
        return 0.0;
    }

    SumTypeFromReturn!(fn1, fn2) obj;
    obj.match!((int x) {}, (double x) {});
}
