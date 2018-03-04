/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type;

import dextool.plugin.mutate.backend.type;
import dextool.plugin.mutate.type : MutationKind;

public import dextool.plugin.mutate.backend.mutation_type.abs;
public import dextool.plugin.mutate.backend.mutation_type.aor;
public import dextool.plugin.mutate.backend.mutation_type.cor;
public import dextool.plugin.mutate.backend.mutation_type.dcc;
public import dextool.plugin.mutate.backend.mutation_type.dcr;
public import dextool.plugin.mutate.backend.mutation_type.lcr;
public import dextool.plugin.mutate.backend.mutation_type.ror;
public import dextool.plugin.mutate.backend.mutation_type.sdl;
public import dextool.plugin.mutate.backend.mutation_type.uoi;

@safe:

/** Expand a mutation to all kinds at the same mutation point that would result in the same mutation being performed.
 */
Mutation.Kind[] broadcast(const Mutation.Kind k) {
    switch (k) with (Mutation.Kind) {
    case rorLT:
        goto case;
    case rorpLT:
        return [rorLT, rorpLT];
    case rorLE:
        goto case;
    case rorpLE:
        return [rorLE, rorpLE];
    case rorGT:
        goto case;
    case rorpGT:
        return [rorGT, rorpGT];
    case rorGE:
        goto case;
    case rorpGE:
        return [rorGE, rorpGE];
    case rorEQ:
        goto case;
    case rorpEQ:
        return [rorEQ, rorpEQ];
    case rorNE:
        goto case;
    case rorpNE:
        return [rorNE, rorpNE];

    default:
        return [k];
    }
}

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
