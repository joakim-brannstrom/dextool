/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.cor;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

/// What the operator should be replaced by.
auto corOpMutations(Mutation.Kind is_a) @safe pure nothrow {
    if (is_a == Mutation.Kind.corAnd) {
        return [Mutation.Kind.corEQ];
    } else if (is_a == Mutation.Kind.corOr) {
        return [Mutation.Kind.corNE];
    }

    return null;
}

/// What the expression should be replaced by.
auto corExprMutations(Mutation.Kind is_a) @safe pure nothrow {
    if (is_a == Mutation.Kind.corAnd) {
        return [Mutation.Kind.corFalse];
    } else if (is_a == Mutation.Kind.corOr) {
        return [Mutation.Kind.corTrue];
    }

    return null;
}

immutable Mutation.Kind[OpKind] isCor;
immutable Mutation.Kind[] corMutationsRaw;

shared static this() {
    with (OpKind) {
    isCor = cast(immutable)
        [
        LAnd: Mutation.Kind.corAnd, // "&&"
        LOr: Mutation.Kind.corOr, // "||"
        OO_AmpAmp: Mutation.Kind.corAnd, // "&&"
        OO_PipePipe: Mutation.Kind.corOr, // "||"
        ];
    }

    with (Mutation.Kind) {
        corMutationsRaw = [corFalse, corLhs, corRhs, corEQ, corNE, corTrue];
    }
}
