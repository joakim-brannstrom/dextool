/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
Authors: Jacob Carlborg
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)

Copied from DStep.

Convenient functions for a set.
*/
module dextool.set;

import std.algorithm : filter;
import std.range : ElementType, isOutputRange;

@safe:

struct Set(T) {
    alias Type = void[0][T];
    Type data;

    bool opBinaryRight(string op)(T key) if (op == "in") {
        return (key in data) !is null;
    }

    bool empty() @safe pure nothrow const @nogc {
        return data.length == 0;
    }

    size_t length() @safe pure nothrow const @nogc {
        return data.length;
    }

    void add(T value) @safe pure nothrow {
        data[value] = (void[0]).init;
    }

    void add(Set!T set) @safe pure nothrow {
        add(set.data);
    }

    void add(Type set) @safe pure nothrow {
        foreach (key; set.byKey)
            data[key] = (void[0]).init;
    }

    void add(Range)(Range r) @safe pure nothrow if (is(ElementType!Range == T)) {
        foreach (v; r)
            data[v] = (void[0]).init;
    }

    void remove(T value) {
        data.remove(value);
    }

    Set!T clone() @safe pure nothrow {
        Set!T result;
        result.add(data);
        return result;
    }

    bool contains(T value) {
        return (value in data) !is null;
    }

    /** The set difference according to Set Theory.
     *
     * It is the set of all members in self that are not members of set.
     */
    Set!T setDifference(Set!T set) {
        typeof(this) r;
        foreach (k; toRange.filter!(a => !set.contains(a)))
            r.add(k);

        return r;
    }

    /** The symmetric difference according to Set Theory.
     *
     * It is the set of all objects that are a member of exactly one of self and set.
     */
    Set!T symmetricDifference(Set!T set) {
        typeof(this) r;
        foreach (k; toRange.filter!(a => !contains(a)))
            r.add(k);
        foreach (k; toRange.filter!(a => !contains(a)))
            r.add(k);

        return r;
    }

    /** The intersection according to Set Theory.
     *
     * It is the set of all objects that are members of both self and set.
     */
    Set!T intersect(Set!T set) {

        typeof(this) r;
        foreach (k; toRange.filter!(a => set.contains(a)))
            r.add(k);

        return r;
    }

    auto toArray() {
        import std.array : appender;

        auto app = appender!(T[])();
        foreach (key; toRange)
            app.put(key);
        return app.data;
    }

    auto toRange() inout {
        return data.byKey;
    }

    string toString() {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;

        formattedWrite(w, "Set!(%s)(%-(%s, %))", T.stringof, toRange);
    }
}

auto toSet(RangeT)(RangeT range) {
    import std.traits : Unqual;

    alias T = ElementType!RangeT;

    Set!(Unqual!T) result;
    foreach (item; range)
        result.add(item);
    return result;
}
