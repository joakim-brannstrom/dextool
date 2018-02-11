/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.dcc;

import dextool.plugin.mutate.backend.mutation_type.lcr;
import dextool.plugin.mutate.backend.mutation_type.ror;
import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

Mutation.Kind[] dccBranchMutations() @safe pure nothrow {
    return dccBranchMutationsRaw.dup;
}

Mutation.Kind[] dccCaseMutations() @safe pure nothrow {
    return dccCaseMutationsRaw.dup;
}

immutable bool[OpKind] isDcc;
immutable Mutation.Kind[] dccBranchMutationsRaw;
immutable Mutation.Kind[] dccCaseMutationsRaw;

shared static this() {
    with (OpKind) {
        bool[OpKind] is_dcc;
        foreach (k; isLcr.byKey)
            is_dcc[k] = true;
        foreach (k; isRor.byKey)
            is_dcc[k] = true;

        isDcc = cast(immutable) is_dcc.dup;
    }

    with (Mutation.Kind) {
        dccBranchMutationsRaw = [dccTrue, dccFalse];
        dccCaseMutationsRaw = [dccBomb];
    }
}
