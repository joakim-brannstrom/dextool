/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains functionality to calculate hashes for use as e.g.
checksums. The intention is to have the *same* algorithm being used for the
same *things* in deXtool.

This is to make it easier to integrate with deXtool produced data.

**Prefer** the 128-bit hash.

Use the 64-bit if you have to for compatibility reasons with other services not
part of dextool.

**Warning**: These may not be endian independent.

TODO: rename ChecksumXX to HashXX.
*/
module dextool.hash;

import std.digest.crc : CRC64ISO;
import std.digest.murmurhash : MurmurHash3;

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

ulong toUlong(ubyte[8] v) @trusted pure nothrow @nogc {
    return *(cast(size_t*)&v);
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

/// Make a 32bit hash.
// TODO: deprecate this. Should use the 128-bit.
ulong makeHash(T)(T raw) @safe pure nothrow @nogc {
    import std.digest.crc;

    if (raw is null)
        return 0;
    ubyte[4] hash = crc32Of(raw);
    return (hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3];
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

    size_t toHash() @safe nothrow const {
        return (c0 + c1).toSizeT;
    }

    bool opEquals(const typeof(this) o) const nothrow @safe {
        return c0 == o.c0 && c1 == o.c1;
    }

    import std.format : FormatSpec;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formatValue, formattedWrite;
        import std.range.primitives : put;

        if (fmt.spec == 'x')
            formattedWrite(w, "%x%x", c0, c1);
        else
            formattedWrite(w, "%s%s", c0, c1);
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
 * It is intended to be generically used in deXtool when such a checksum is needed.
 *
 * CRC64 ISO is used because there exist implementations in other languages
 * which makes it possible to calculate the checksum in e.g. python and compare
 * with the one from deXtool.
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

    import std.format : FormatSpec;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formatValue, formattedWrite;
        import std.range.primitives : put;

        if (fmt.spec == 'x')
            formattedWrite(w, "%x", c0);
        else
            formattedWrite(w, "%s", c0);
    }
}
