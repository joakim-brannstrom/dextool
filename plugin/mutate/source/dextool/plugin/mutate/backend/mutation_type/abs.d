/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.abs;

import dextool.plugin.mutate.backend.type;

Mutation.Kind[] absMutations() @safe pure nothrow {
    return absMutationsRaw.dup;
}

immutable Mutation.Kind[] absMutationsRaw;

shared static this() {
    with (Mutation.Kind) {
        absMutationsRaw = [absPos, absNeg, absZero,];
    }
}
