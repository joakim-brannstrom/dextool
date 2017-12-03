/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.type;

/// The kind of mutation to perform
enum MutationKind {
    /// any kind of mutation
    any,
    /// Relational operator replacement
    ror,
    /// Logical connector replacement
    lcr,
    /// Arithmetic operator replacement
    aor,
    /// Unary operator insert
    uoi,
    /// Absolute value replacement
    abs,
}
