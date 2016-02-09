// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.utility.range;
import std.range : isForwardRange;

@nogc struct ArrayRange(T) if (isArray!T) {
    @property auto front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range of " ~ T.stringof);
        return payload[0];
    }

    @property auto back() @safe pure nothrow {
        assert(!empty, "Can't get back of an empty range of " ~ T.stringof);
        return payload[$ - 1];
    }

    @property void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range of " ~ T.stringof);
        payload = payload[1 .. $];
    }

    @property void popBack() @safe pure nothrow {
        assert(!empty, "Can't pop back of an empty range of " ~ T.stringof);
        payload = payload[0 .. $ - 1];
    }

    @property bool empty() @safe pure nothrow const {
        return payload.length == 0;
    }

    @property auto save() @safe pure nothrow {
        return typeof(this)(payload);
    }

    @property auto opIndex(size_t i) {
        return payload[i];
    }

    @property auto opIndex() {
        return payload[];
    }

    @property typeof(this) opSlice(size_t lower, size_t upper) {
        return ArrayRange(payload[lower .. upper]);
    }

    @property auto length() @safe pure nothrow {
        return payload.length;
    }

private:
    T payload;
}

auto arrayRange(T)(T s) if (isArray!T) {
    return ArrayRange!(T)(s);
}

//TODO replacing the is expression with "true" seems to be the same.
//investigate the effect
private enum isArray(T : Tx[], Tx) = is(T : Tx[]);
