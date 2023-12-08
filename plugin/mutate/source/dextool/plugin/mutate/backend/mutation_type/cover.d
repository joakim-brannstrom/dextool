/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

How mutants of different types cover other mutants on the same source code
location that have the status unknown.

Mutation.Kind,status -> Mutation.Kind
*/
module dextool.plugin.mutate.backend.mutation_type.cover;

import std.traits : EnumMembers;

import my.set;

import dextool.plugin.mutate.backend.mutation_type.aor;
import dextool.plugin.mutate.backend.mutation_type.aors;
import dextool.plugin.mutate.backend.mutation_type.cr;
import dextool.plugin.mutate.backend.mutation_type.dcr;
import dextool.plugin.mutate.backend.mutation_type.lcr;
import dextool.plugin.mutate.backend.mutation_type.ror;
import dextool.plugin.mutate.backend.mutation_type.uoi;
import dextool.plugin.mutate.backend.type : Mutation;

struct Cover {
    Mutation.Kind kind;
    Mutation.Status status;

    size_t toHash() @safe pure nothrow const @nogc scope {
        auto a = kind.hashOf();
        return status.hashOf(a);
    }
}

const Mutation.Kind[][Cover] covers;

shared static this() {
    Mutation.Kind[][Cover] s;
    scope (success)
        covers = cast(const) s;

    s[Cover(Mutation.Kind.stmtDel, Mutation.Status.alive)] = [
        EnumMembers!(Mutation.Kind)
    ];

    // one surviving is enough. when a user fix it then the others are
    // executed. Most probably killed then.
    // lcrb not needed because it is just binary. no use in doing a cover operation.
    foreach (k; aorMutationsAll)
        s[Cover(k, Mutation.Status.alive)] = aorMutationsAll.dup;
    foreach (k; aorsMutationsAll)
        s[Cover(k, Mutation.Status.alive)] = aorsMutationsAll.dup;
    foreach (k; crMutationsAll)
        s[Cover(k, Mutation.Status.alive)] = crMutationsAll.dup;
    foreach (k; dcrMutationsAll)
        s[Cover(k, Mutation.Status.alive)] = dcrMutationsAll.dup;
    foreach (k; lcrMutationsAll)
        s[Cover(k, Mutation.Status.alive)] = lcrMutationsAll.dup;
    foreach (k; rorMutationsAll)
        s[Cover(k, Mutation.Status.alive)] = rorMutationsAll.dup;
    foreach (k; rorpMutationsAll)
        s[Cover(k, Mutation.Status.alive)] = rorpMutationsAll.dup;
    foreach (k; uoiLvalueMutations)
        s[Cover(k, Mutation.Status.alive)] = uoiLvalueMutations.dup;
    foreach (k; uoiRvalueMutations)
        s[Cover(k, Mutation.Status.alive)] = uoiRvalueMutations.dup;
}
