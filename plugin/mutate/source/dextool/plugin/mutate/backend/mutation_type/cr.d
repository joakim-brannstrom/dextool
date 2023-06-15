/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.cr;

import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.analyze.ast;

Mutation.Kind[] crMutations(Kind kind) @safe pure nothrow {
    switch (kind) {
    case Kind.Literal:
        return [Mutation.Kind.crZeroInt];
    case Kind.FloatLiteral:
        return [Mutation.Kind.crZeroFloat];
    default:
    }

    return null;
}

immutable Mutation.Kind[] crMutationsAll;

shared static this() {
    with (Mutation.Kind) {
        crMutationsAll = [crZeroInt, crZeroFloat];
    }
}
