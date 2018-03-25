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
    /// Relational operator replacement for pointers
    rorp,
    /// Logical connector replacement
    lcr,
    /// Arithmetic operator replacement
    aor,
    /// Unary operator insert
    uoi,
    /// Absolute value replacement
    abs,
    /// Statement deletion
    sdl,
    /// Conditional operator replacement
    cor,
    /// Decision/Condition Coverage
    dcc,
    /// Decision/Condition Requirement
    dcr,
}

/// The order the mutations are done when running in test_mutants mode
enum MutationOrder {
    random,
    consecutive,
}

/// The kind of report to generate to the user
enum ReportKind {
    /// As a plain text output
    plain,
    /// As a markdown report that
    markdown,
    /// As compiler warnings and a fix-it hint for the mutation
    compiler,
    /// As a JSON model
    json,
}

/// The level of reporting
enum ReportLevel {
    /// Report a summary of the mutation statistics
    summary,
    /// Report alive mutants
    alive,
    /// Report all mutants
    all
}

/// Administrative operation to perform
enum AdminOperation {
    reset,
    remove
}
