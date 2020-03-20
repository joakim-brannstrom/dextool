/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.dcc;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

import dextool.plugin.mutate.backend.analyze.ast;

Mutation.Kind[] dccMutations(Kind operator) @safe pure nothrow {
    typeof(return) rval;

    // an operator is a predicate, leaf.
    // the condition is obviously the top node.
    switch (operator) with (Mutation.Kind) {
    case Kind.Call:
        goto case;
    case Kind.Expr:
        goto case;
    case Kind.OpAnd:
        goto case;
    case Kind.OpOr:
        goto case;
    case Kind.OpLess:
        goto case;
    case Kind.OpGreater:
        goto case;
    case Kind.OpLessEq:
        goto case;
    case Kind.OpGreaterEq:
        goto case;
    case Kind.OpEqual:
        goto case;
    case Kind.OpNotEqual:
        goto case;
    case Kind.Condition:
        rval = [dccTrue, dccFalse];
        break;
    case Kind.Branch:
        rval = [dccBomb];
        break;
    default:
    }

    return rval;
}

immutable Mutation.Kind[] dccBranchMutationsRaw;
immutable Mutation.Kind[] dccCaseMutationsRaw;

shared static this() {
    with (Mutation.Kind) {
        dccBranchMutationsRaw = [dccTrue, dccFalse];
        dccCaseMutationsRaw = [dccBomb];
    }
}
