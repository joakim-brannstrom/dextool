/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

A RAII vector that uses GC memory. It is not meant to be performant but rather
convenient. The intention is to support put/pop for front and back and
convenient range operations.
*/
module my.container.vector;

import std.array : array;
import std.range : isForwardRange;

auto vector(T)(T[] data) {
    return Vector!T(data);
}

struct Vector(T) {
    T[] data;

    void putFront(T a) {
        data = [a] ~ data;
    }

    void put(T a) {
        data ~= a;
    }

    void put(T[] a) {
        data ~= a;
    }

    void popBack() {
        data = data[0 .. $ - 1];
    }

    T back() {
        return data[$ - 1];
    }

    T front() {
        assert(!empty, "Can't get front of an empty range");
        return data[0];
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");
        data = data[1 .. $];
    }

    void clear() {
        data = null;
    }

    bool empty() const {
        return data.length == 0;
    }

    size_t length() const {
        return data.length;
    }

    Vector!T range() {
        return Vector!T(data);
    }

    ref inout(T) opIndex(long index) scope return inout {
        return data[index];
    }

    /// Returns a new vector after appending to the given vector.
    Vector opBinary(string s, T)(auto ref T other) const 
            if (s == "~" && is(Unqual!T == Vector)) {
        return vector(data ~ other.data);
    }

    /// Assigns from a range.
    void opAssign(R)(R range) scope if (isForwardRange!(R)) {
        data ~= range.array;
    }

    void opOpAssign(string op)(T other) scope if (op == "~") {
        put(other);
    }

    /// Append to the vector from a range
    void opOpAssign(string op, R)(scope R range) scope 
            if (op == "~" && isForwardRange!(R)) {
        data ~= range.array;
    }

    size_t opDollar() const {
        return length;
    }

    T[] opSlice() {
        return data;
    }

    /**
       Returns a slice.
       @system because the pointer in the slice might dangle.
     */
    T[] opSlice(size_t start, size_t end) {
        return data[start .. end];
    }

    void opSliceAssign(T value) {
        data[] = value;
    }

    /// Assign all elements in the given range to the given value
    void opSliceAssign(T value, size_t start, size_t end) {
        data[start .. end] = value;
    }

    /// Assign all elements using the given operation and the given value
    void opSliceOpAssign(string op)(E value) scope {
        foreach (ref elt; data)
            mixin(`elt ` ~ op ~ `= value;`);
    }

    /// Assign all elements in the given range  using the given operation and the given value
    void opSliceOpAssign(string op)(E value, long start, long end) scope {
        foreach (ref elt; data[start .. end])
            mixin(`elt ` ~ op ~ `= value;`);
    }

    bool opCast(U)() const scope if (is(U == bool)) {
        return data.length > 0;
    }

    bool opEquals(ref scope const(Vector!(T)) other) const {
        return data == other.data;
    }
}

@("shall put/pop")
unittest {
    Vector!int v;
    v.put(1);
    v.put(2);

    assert(v.front == 1);
    assert(v.back == 2);
    v.popBack;
    assert(v.front == 1);
    assert(v.back == 1);
}

@("shall put/pop")
unittest {
    Vector!int v;
    v.put(1);
    v.put(2);

    assert(v.front == 1);
    assert(v.back == 2);
    v.popFront;
    assert(v.front == 2);
    assert(v.back == 2);
}
