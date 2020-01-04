/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.uoi;

import dextool.plugin.mutate.backend.type;

Mutation.Kind[] uoiLvalueMutations() @safe pure nothrow {
    return uoiLvalueMutationsRaw.dup;
}

Mutation.Kind[] uoiRvalueMutations() @safe pure nothrow {
    return uoiRvalueMutationsRaw.dup;
}

immutable Mutation.Kind[] uoiLvalueMutationsRaw;
immutable Mutation.Kind[] uoiRvalueMutationsRaw;

shared static this() {
    with (Mutation.Kind) {
        // inactivating unary that seem to be nonsense
        uoiLvalueMutationsRaw = [
            uoiPostInc, uoiPostDec, uoiPreInc, uoiPreDec,
            uoiNegation /*, uoiPositive, uoiNegative, uoiAddress,
            uoiIndirection, uoiComplement, uoiSizeof_,*/
        ];
        uoiRvalueMutationsRaw = [
            uoiPreInc, uoiPreDec, uoiNegative, uoiNegation, /*uoiAddress,
            uoiIndirection*, uoiPositive, uoiComplement, uoiSizeof_,*/
        ];

    }
}
