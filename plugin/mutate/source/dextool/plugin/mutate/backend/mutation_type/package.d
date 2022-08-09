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

public import dextool.plugin.mutate.backend.mutation_type.aor;
public import dextool.plugin.mutate.backend.mutation_type.aors;
public import dextool.plugin.mutate.backend.mutation_type.cr;
public import dextool.plugin.mutate.backend.mutation_type.dcr;
public import dextool.plugin.mutate.backend.mutation_type.lcr;
public import dextool.plugin.mutate.backend.mutation_type.lcrb;
public import dextool.plugin.mutate.backend.mutation_type.ror;
public import dextool.plugin.mutate.backend.mutation_type.sdl;
public import dextool.plugin.mutate.backend.mutation_type.uoi;

@safe:

Mutation.Kind[] toInternal(const MutationKind[] k) @safe pure nothrow {
    import std.algorithm : map, joiner;
    import std.array : array;
    import std.traits : EnumMembers;

    auto kinds(const MutationKind k) {
        final switch (k) with (MutationKind) {
        case all:
            return [EnumMembers!(Mutation.Kind)];
        case ror:
            return rorMutationsAll.dup;
        case rorp:
            return rorpMutationsAll.dup;
        case lcr:
            return lcrMutationsAll.dup;
        case aor:
            return aorMutationsAll.dup ~ aorAssignMutationsAll;
        case aors:
            return aorsMutationsAll.dup ~ aorsAssignMutationsAll;
        case uoi:
            return uoiLvalueMutations;
        case sdl:
            return stmtDelMutations;
        case dcr:
            return dcrMutationsAll.dup;
        case lcrb:
            return lcrbMutationsAll.dup ~ lcrbAssignMutationsAll.dup;
        case cr:
            return crMutationsAll.dup;
        }
    }

    return (k is null ? [MutationKind.all] : k).map!(a => kinds(a)).joiner.array;
}

/// Convert the internal mutation kind to those that are presented to the user via the CLI.
MutationKind toUser(Mutation.Kind k) @safe nothrow {
    return fromInteralKindToUserKind[k];
}

immutable string[MutationKind] mutationDescription;

private:

immutable MutationKind[Mutation.Kind] fromInteralKindToUserKind;

shared static this() {
    import std.traits : EnumMembers;

    static foreach (const user_kind; EnumMembers!MutationKind) {
        foreach (const internal_kind; toInternal([user_kind])) {
            fromInteralKindToUserKind[internal_kind] = user_kind;
        }
    }

    mutationDescription[MutationKind.ror] = "Relational operator replacement";
    mutationDescription[MutationKind.rorp] = "Relational operator replacement for pointers";
    mutationDescription[MutationKind.lcr] = "Logical connector replacement";
    mutationDescription[MutationKind.aor] = "Arithmetic operator replacement";
    mutationDescription[MutationKind.uoi] = "Unary operator insert";
    mutationDescription[MutationKind.sdl] = "Statement deletion";
    mutationDescription[MutationKind.dcr] = "Decision/Condition requirement";
    mutationDescription[MutationKind.lcrb] = "Logical connector replacement bit-wise";
    mutationDescription[MutationKind.aors] = "Arithmetic operator replacement simple";
    mutationDescription[MutationKind.cr] = "Constant replacement";
}
