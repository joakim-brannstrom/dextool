/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
Authors: Jacob Carlborg
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)

Copied from DStep.

Convenient functions for a set.
*/
module dextool.set;

import std.range : ElementType;

alias Set(T) = void[0][T];

void add(T)(ref void[0][T] self, T value) {
    self[value] = (void[0]).init;
}

/// Merge set into self
void add(T)(ref void[0][T] self, void[0][T] set) {
    foreach (key; set.byKey) {
        self.add(key);
    }
}

void remove(T)(ref void[0][T] self, T value) {
    self.remove(value);
}

Set!T clone(T)(ref void[0][T] self) {
    Set!T result;
    result.add(self);
    return result;
}

bool contains(T)(inout(void[0][T]) set, T value) {
    return (value in set) !is null;
}

/** The set difference according to Set Theory.
 *
 * It is the set of all members in `self` that are not members of `set`.
 */
SetT setDifference(SetT)(ref SetT self, SetT set) {
    import std.algorithm : filter;

    SetT r;
    foreach (k; self.byKey.filter!(a => !set.contains(a))) {
        r.add(k);
    }

    return r;
}

/** The symmetric difference according to Set Theory.
 *
 * It is the set of all objects that are a member of exactly one of `self` and `set`.
 */
SetT symmetricDifference(SetT)(ref SetT self, SetT set) {
    import std.algorithm : filter;

    SetT r;
    foreach (k; self.byKey.filter!(a => !set.contains(a))) {
        r.add(k);
    }
    foreach (k; set.byKey.filter!(a => !self.contains(a))) {
        r.add(k);
    }

    return r;
}

/** The intersection according to Set Theory.
 *
 * It is the set of all objects that are members of both `self` and `set`.
 */
SetT intersect(SetT)(ref SetT self, SetT set) {
    import std.algorithm : filter;

    SetT r;
    foreach (k; self.byKey.filter!(a => set.contains(a))) {
        r.add(k);
    }

    return r;
}

Set!T setFromList(T)(T[] list) {
    import std.traits;

    Set!(Unqual!T) result;

    foreach (item; list)
        result.add(item);

    return result;
}

Set!T setFromRange(T, RangeT)(RangeT range) if (is(ElementType!RangeT == T)) {
    import std.traits;

    Set!(Unqual!T) result;

    foreach (item; range)
        result.add(item);

    return result;
}

auto setToList(T)(ref Set!T set) {
    import std.array : appender;

    auto app = appender!(T[])();
    foreach (key; set.byKey)
        app.put(key);
    return app.data;
}
