/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.lcrb;

import std.typecons : Tuple;

import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.analyze.ast;

immutable Mutation.Kind[] lcrbMutationsAll;
immutable Mutation.Kind[] lcrbAssignMutationsAll;

shared static this() {
    with (Mutation.Kind) {
        lcrbMutationsAll = [lcrbAnd, lcrbOr, lcrbLhs, lcrbRhs];
        lcrbAssignMutationsAll = [lcrbOrAssign, lcrbAndAssign];
    }
}
