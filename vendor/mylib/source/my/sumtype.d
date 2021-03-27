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
