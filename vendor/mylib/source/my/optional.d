/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Definition of an optional type using sumtype.
*/
module my.optional;

import std.traits : isSomeFunction, ReturnType;

import sumtype;

alias Optional(T) = SumType!(None, Some!T);

/// Optional with no value
Optional!T none(T)() {
    return typeof(return)(None.init);
}

/// An optional containing a value.
Optional!T some(T)(T value) {
    return typeof(return)(Some!T(value));
}

/// No value in the Optional.
struct None {
}

/// A value.
struct Some(T) {
    T value;
    alias value this;
}

bool hasValue(T : SumType!(None, Some!U), U)(T v) {
    return match!((None a) => false, (Some!U a) => true)(v);
}

U orElse(T, U)(T v, U or) if (is(T == Optional!U)) {
    return match!((None a) => or, (Some!U a) => a.value)(v);
}

T orElse(T : SumType!(None, Some!U), U)(T v, T or) {
    return match!((None a) => or, (Some!U a) => T(a))(v);
}

T orElse(T : SumType!(None, Some!U), U, OrT)(T v, OrT or)
        if (isSomeFunction!OrT && is(ReturnType!OrT == T)) {
    return match!((None a) => or(), (Some!U a) => T(a))(v);
}

U orElse(T : SumType!(None, Some!U), U, OrT)(T v, OrT or)
        if (isSomeFunction!OrT && is(ReturnType!OrT == U)) {
    return match!((None a) => or(), (Some!U a) => a.value)(v);
}

@("shall chain multiple optional")
unittest {
    static int fn1() {
        return 5;
    }

    static Optional!int fn2() {
        return some(5);
    }

    assert(none!int.hasValue == false);
    assert(some(5).hasValue == true);

    assert(none!int.orElse(5) == 5);
    assert(none!int.orElse(() => 5) == 5);
    assert(none!int.orElse(&fn1) == 5);

    assert(some(10).orElse(5) == 10);
    assert(some(10).orElse(() => 5) == 10);
    assert(some(10).orElse(&fn1) == 10);

    assert(none!int.orElse(some(5)) == some(5));
    assert(none!int.orElse(() => some(5)) == some(5));
    assert(none!int.orElse(&fn2) == some(5));

    assert(some(10).orElse(some(5)) == some(10));
    assert(some(10).orElse(() => some(5)) == some(10));
    assert(some(10).orElse(&fn2) == some(10));
}
