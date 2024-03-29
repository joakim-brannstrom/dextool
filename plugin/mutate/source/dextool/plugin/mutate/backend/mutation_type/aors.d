/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.aors;

import dextool.plugin.mutate.backend.type : Mutation;

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
