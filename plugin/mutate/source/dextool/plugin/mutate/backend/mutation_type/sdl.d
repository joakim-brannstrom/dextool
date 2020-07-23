/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.sdl;

import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.analyze.ast;

Mutation.Kind[] stmtDelMutations() @safe pure nothrow {
    return stmtDelMutationsRaw.dup;
}

Mutation.Kind[] stmtDelMutations(Kind operator) @safe pure nothrow {
    Mutation.Kind[] rval;

    switch (operator) with (Mutation.Kind) {
    case Kind.Return:
        goto case;
    case Kind.Block:
        goto case;
    case Kind.BinaryOp:
        goto case;
    case Kind.OpAssign:
        goto case;
    case Kind.OpAssignAdd:
        goto case;
    case Kind.OpAssignAndBitwise:
        goto case;
    case Kind.OpAssignDiv:
        goto case;
    case Kind.OpAssignMod:
        goto case;
    case Kind.OpAssignMul:
        goto case;
    case Kind.OpAssignOrBitwise:
        goto case;
    case Kind.OpAssignSub:
        goto case;
    case Kind.Call:
        rval = [stmtDel];
        break;
    default:
    }

    return rval;
}

immutable Mutation.Kind[] stmtDelMutationsRaw;

shared static this() {
    with (Mutation.Kind) {
        stmtDelMutationsRaw = [stmtDel];
    }
}
