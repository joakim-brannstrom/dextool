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
size_t makeHash(T)(T raw) @safe pure nothrow @nogc {
    import std.digest.crc;

    size_t value = 0;

    if (raw is null)
        return value;
    ubyte[4] hash = crc32Of(raw);
    return value ^ ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
}
