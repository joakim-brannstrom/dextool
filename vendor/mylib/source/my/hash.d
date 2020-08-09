/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

A convenient library for calculating the hash of bits of data.
*/
module my.hash;

import std.digest.crc : CRC64ISO;
import std.digest.murmurhash : MurmurHash3;

import std.format : FormatSpec;
import std.format : formatValue, formattedWrite;
import std.range.primitives : put;

alias BuildChecksum64 = CRC64ISO;
alias Checksum64 = Crc64Iso;
alias makeChecksum64 = makeCrc64Iso;
alias toChecksum64 = toCrc64Iso;

alias BuildChecksum128 = MurmurHash3!(128, 64);
alias Checksum128 = Murmur3;
alias makeChecksum128 = makeMurmur3;
alias toChecksum128 = toMurmur3;

/// Convert a value to its ubyte representation.
auto toBytes(T)(T v) @trusted pure nothrow @nogc {
    import std.conv : emplace;

    ubyte[T.sizeof] d;
    T* p = cast(T*)&d;
    cast(void) emplace!T(p, v);
    return d;
}

long toLong(ubyte[8] v) @trusted pure nothrow @nogc {
    return *(cast(long*)&v);
}

ulong toUlong(ubyte[8] v) @trusted pure nothrow @nogc {
    return *(cast(ulong*)&v);
}

/// Convert to size_to for use in e.g. operator overload toHash.
size_t toSizeT(T)(T v) if (is(T : uint) || is(T : ulong)) {
    static if (size_t.sizeof == 4 && T.sizeof == 8)
        return cast(uint) v + cast(uint)(v >> 32);
    else
        return v;
}

/// ditto.
size_t toSizeT(const(ubyte)[4] v) @trusted pure nothrow @nogc {
    return toSizeT(*(cast(const(uint)*)&v));
}

/// ditto.
size_t toSizeT(const(ubyte)[8] v) @trusted pure nothrow @nogc {
    return toSizeT(*(cast(const(ulong)*)&v));
}

Murmur3 makeMurmur3(const(ubyte)[] p) @safe nothrow {
    BuildChecksum128 hasher;
    hasher.put(p);
    return toMurmur3(hasher);
}

/// Convenient function to convert to a checksum type.
Murmur3 toMurmur3(const(ubyte)[16] p) @trusted pure nothrow @nogc {
    ulong a = *(cast(ulong*)&p[0]);
    ulong b = *(cast(ulong*)&p[8]);
    return Murmur3(a, b);
}

Murmur3 toMurmur3(ref BuildChecksum128 h) @safe pure nothrow @nogc {
    return toMurmur3(h.finish);
}

/// 128bit hash.
struct Murmur3 {
    ulong c0;
    ulong c1;

    size_t toHash() @safe nothrow const pure @nogc {
        return (c0 + c1).toSizeT;
    }

    bool opEquals(const typeof(this) o) const nothrow @safe pure @nogc {
        return c0 == o.c0 && c1 == o.c1;
    }

    int opCmp(ref const typeof(this) rhs) @safe pure nothrow const @nogc {
        // return -1 if "this" is less than rhs, 1 if bigger and zero equal
        if (c0 < rhs.c0)
            return -1;
        if (c0 > rhs.c0)
            return 1;
        if (c1 < rhs.c1)
            return -1;
        if (c1 > rhs.c1)
            return 1;
        return 0;
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        if (fmt.spec == 'x')
            formattedWrite(w, "%x_%x", c0, c1);
        else
            formattedWrite(w, "%s_%s", c0, c1);
    }
}

/// Create a 64bit hash.
Crc64Iso makeCrc64Iso(const(ubyte)[] p) @trusted pure nothrow @nogc {
    BuildChecksum64 hash;
    hash.put(p);
    return toCrc64Iso(hash);
}

/// Convenient function to convert to a checksum type.
Crc64Iso toCrc64Iso(const(ubyte)[8] p) @trusted pure nothrow @nogc {
    return Crc64Iso(*(cast(ulong*)&p[0]));
}

Crc64Iso toCrc64Iso(ref BuildChecksum64 h) @trusted pure nothrow @nogc {
    ubyte[8] v = h.peek;
    return Crc64Iso(*(cast(ulong*)&v[0]));
}

/** 64-bit checksum.
 *
 * It is intended to be generically used in Dextool when such a checksum is needed.
 *
 * CRC64 ISO is used because there exist implementations in other languages
 * which makes it possible to calculate the checksum in e.g. python and compare
 * with the one from Dextool.
 *
 * TODO: check if python have a 64ISO or 64ECMA implementation.
 */
struct Crc64Iso {
    ulong c0;

    size_t toHash() @safe pure nothrow const @nogc scope {
        return c0;
    }

    bool opEquals(const typeof(this) s) @safe pure nothrow const @nogc scope {
        return c0 == s.c0;
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        if (fmt.spec == 'x')
            formattedWrite(w, "%x", c0);
        else
            formattedWrite(w, "%s", c0);
    }
}
