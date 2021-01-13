/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.aors;

import dextool.plugin.mutate.backend.type;
import dextool.plugin.mutate.backend.analyze.ast;

Mutation.Kind aorsMutations(Kind operand) @safe {
    Mutation.Kind rval;
    switch (operand) with (Mutation.Kind) {
    case Kind.OpAdd:
        rval = aorsSub;
        break;
    case Kind.OpDiv:
        rval = aorsMul;
        break;
    case Kind.OpMod:
        rval = aorsDiv;
        break;
    case Kind.OpMul:
        rval = aorsDiv;
        break;
    case Kind.OpSub:
        rval = aorsAdd;
        break;
    case Kind.OpAssignAdd:
        rval = aorsSubAssign;
        break;
    case Kind.OpAssignDiv:
        rval = aorsMulAssign;
        break;
    case Kind.OpAssignMod:
        rval = aorsDivAssign;
        break;
    case Kind.OpAssignMul:
        rval = aorsDivAssign;
        break;
    case Kind.OpAssignSub:
        rval = aorsAddAssign;
        break;
    default:
    }

    return rval;
}

immutable Mutation.Kind[] aorsMutationsAll;
immutable Mutation.Kind[] aorsAssignMutationsAll;

shared static this() {
    with (Mutation.Kind) {
        aorsMutationsAll = [aorsMul, aorsDiv, aorsAdd, aorsSub];
        aorsAssignMutationsAll = [
            aorsMulAssign, aorsDivAssign, aorsAddAssign, aorsSubAssign
        ];
    }
}
