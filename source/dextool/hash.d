/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.hash;

/// Make a hash out of the raw data.
ulong makeHash(T)(T raw) @safe pure nothrow @nogc {
    import std.digest.crc;

    ulong value = 0;

    if (raw is null)
        return value;
    ubyte[4] hash = crc32Of(raw);
    return value ^ ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
}

Murmur3 makeMurmur3(const(ubyte)[] p) @trusted nothrow {
    import std.digest.murmurhash;

    MurmurHash3!(128, 64) hasher;
    hasher.put(p);

    ubyte[16] h = hasher.finish;

    ulong a = *(cast(ulong*)&h[0]);
    ulong b = *(cast(ulong*)&h[8]);

    return Murmur3(a, b);
}

/// Checksum of the content of a file.
struct Murmur3 {
    ulong c0;
    ulong c1;

    bool opEquals(const this o) nothrow @safe {
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
