/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.dcr;

import logger = std.experimental.logger;

import dextool.plugin.mutate.backend.type;
import dextool.plugin.mutate.backend.analyze.ast;

/// Information used to intelligently generate ror mutants;
struct DcrInfo {
    Kind operator;
    Type ty;
}

Mutation.Kind[] dcrMutations(DcrInfo info) @safe {
    import std.algorithm : among;

    typeof(return) rval;
    // an operator is a predicate, leaf.
    // the condition is obviously the top node.
    switch (info.operator) with (Mutation.Kind) {
    case Kind.Call:
        goto case;
    case Kind.Expr:
        // conservative only replace an expr if it is a boolean.
        // replace the functions body with return true/false;
        if (info.ty !is null && info.ty.kind == TypeKind.boolean)
            rval = [dcrTrue, dcrFalse];
        break;
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
        // pessimistic, no type then do nothing.
        // discrete because it degenerate to a boolean.
        if (info.ty !is null
                && info.ty.kind.among(TypeKind.boolean, TypeKind.discrete))
            rval = [dcrTrue, dcrFalse];
        break;
    default:
    }

    return rval;
}

immutable Mutation.Kind[] dcrMutationsAll;

shared static this() {
    with (Mutation.Kind) {
        dcrMutationsAll = [dcrTrue, dcrFalse];
    }
}
