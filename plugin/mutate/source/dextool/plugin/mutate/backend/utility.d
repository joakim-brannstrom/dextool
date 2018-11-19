/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.utility;

import core.time : Duration;
import std.algorithm : filter;

import dextool.type : Path, AbsolutePath;

public import dextool.plugin.mutate.backend.type;
public import dextool.plugin.mutate.backend.mutation_type;
public import dextool.clang_extensions : OpKind;
public import dextool.plugin.mutate.backend.interface_ : SafeInput;

@safe:

Path trustedRelativePath(string p, AbsolutePath root) @trusted {
    import std.path : relativePath;

    return relativePath(p, root).Path;
}

/**
 * trusted: void[] is perfectly representable as ubyte[] accoding to the specification.
 */
Checksum checksum(const(ubyte)[] a) {
    import dextool.hash : makeMurmur3;

    return makeMurmur3(a);
}

/// Package the values to a checksum.
Checksum checksum(T)(const(T[2]) a) if (T.sizeof == 8) {
    return Checksum(cast(ulong) a[0], cast(ulong) a[1]);
}

/// Package the values to a checksum.
Checksum checksum(T)(const T a, const T b) if (T.sizeof == 8) {
    return Checksum(cast(ulong) a, cast(ulong) b);
}

/// Sleep for a random time that is min_ + rnd(0, span msecs)
void rndSleep(Duration min_, int span) nothrow @trusted {
    import core.thread : Thread;
    import core.time : dur;
    import std.random : uniform;

    auto t_span = () {
        try {
            return uniform(0, span).dur!"msecs";
        } catch (Exception e) {
        }
        return span.dur!"msecs";
    }();

    Thread.sleep(min_ + t_span);
}
