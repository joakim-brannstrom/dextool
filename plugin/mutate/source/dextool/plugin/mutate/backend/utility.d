/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.utility;

import dextool.plugin.mutate.backend.type;

/**
 * trusted: void[] is perfectly representable as ubyte[] accoding to the specification.
 */
Checksum checksum(const(ubyte)[] a) @safe {
    import dextool.hash : makeMurmur3;

    return makeMurmur3(a);
}

/// Package the values to a checksum.
Checksum ckecksum(T)(const(T[2]) a) @safe if (T.sizeof == 8) {
    return Checksum(cast(ulong) a[0], cast(ulong) a[1]);
}

/// Package the values to a checksum.
Checksum checksum(T)(const T a, const T b) @safe if (T.sizeof == 8) {
    return Checksum(cast(ulong) a, cast(ulong) b);
}
