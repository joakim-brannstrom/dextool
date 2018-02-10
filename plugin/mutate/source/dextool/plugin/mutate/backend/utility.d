/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.utility;

import std.algorithm : filter;

import dextool.type : Path, AbsolutePath;

public import dextool.plugin.mutate.backend.type;
public import dextool.plugin.mutate.backend.mutation_type.abs;
public import dextool.plugin.mutate.backend.mutation_type.aor;
public import dextool.plugin.mutate.backend.mutation_type.cor;
public import dextool.plugin.mutate.backend.mutation_type.dcc;
public import dextool.plugin.mutate.backend.mutation_type.dcr;
public import dextool.plugin.mutate.backend.mutation_type.lcr;
public import dextool.plugin.mutate.backend.mutation_type.ror;
public import dextool.plugin.mutate.backend.mutation_type.sdl;
public import dextool.plugin.mutate.backend.mutation_type.uoi;
public import dextool.clang_extensions : OpKind;

Path trustedRelativePath(string p, AbsolutePath root) @trusted {
    import std.path : relativePath;

    return relativePath(p, root).Path;
}

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

import dextool.plugin.mutate.type : MutationKind;

Mutation.Kind[] toInternal(const MutationKind[] k) @safe pure nothrow {
    import std.algorithm : map, joiner;
    import std.array : array;
    import std.traits : EnumMembers;

    auto kinds(const MutationKind k) {
        final switch (k) with (MutationKind) {
        case any:
            return [EnumMembers!(Mutation.Kind)];
        case ror:
            return rorMutationsAll.dup;
        case rorp:
            return rorpMutationsAll.dup;
        case lcr:
            return lcrMutationsAll.dup;
        case aor:
            return aorMutationsAll.dup ~ aorAssignMutationsAll;
        case uoi:
            return uoiLvalueMutations;
        case abs:
            return absMutations;
        case sdl:
            return stmtDelMutations;
        case cor:
            return corMutationsRaw.dup;
        case dcc:
            return dccBranchMutationsRaw.dup ~ dccCaseMutationsRaw.dup;
        case dcr:
            return dccBranchMutationsRaw.dup ~ dcrCaseMutationsRaw.dup;
        }
    }

    return (k is null ? [MutationKind.any] : k).map!(a => kinds(a)).joiner.array;
}
