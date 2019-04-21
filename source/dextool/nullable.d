/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains a workaround for compiler version 2.082.
It impossible to assign to a Nullable that may have indirections

// TODO: remove this when upgrading the minimal compiler.
*/
module dextool.nullable;

static if (__VERSION__ == 2082L) {
    static assert(0, "DMD 2.082 is not supported because of a bug in Nullable");
} else {
    public import std.typecons : Nullable;
}
