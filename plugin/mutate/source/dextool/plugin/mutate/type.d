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
    /// Logical Connector Replacement Bit-wise
    lcrb,
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
    /// In the CSV format
    csv,
    /// As a HTML report
    html,
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

/// Sections to include in the report
enum ReportSection {
    /// alive mutants
    alive,
    /// killed mutants
    killed,
    /// all mutants
    all_mut,
    /// summary section of the mutation testing
    summary,
    /// mutation statistics
    mut_stat,
    /// test cases that killed the mutant
    tc_killed,
    /// test case statistics
    tc_stat,
    /// test case mapping to killed mutants
    tc_map,
    /// test case suggestions for killing mutants
    tc_suggestion,
    /// Test cases that has killed zero mutants
    tc_killed_no_mutants,
    /// Test cases that kill the same mutants
    tc_full_overlap,
    /// Test cases that kill the same mutants with a mutation ID column
    tc_full_overlap_with_mutation_id,
    /// Test groups defined by the user
    tc_groups,
    /// Minimal set of tests
    tc_min_set,
    /// Similarity between test cases
    tc_similarity,
    /// Similarity between test groups
    tc_groups_similarity,
    /// A treemap of the mutation scores
    treemap,
    /// mutants that has survived that the plugin recommend the user to kill
    mut_recommend_kill,
    /// a section containing a diff and mutants for it
    diff,
    /// report of the mutants that only the test case kill
    tc_unique
}

/// How to sort test cases when reporting them by their kill statistics.
enum ReportKillSortOrder {
    /// From the top down
    top,
    /// From the botton up
    bottom,
}

/// Administrative operation to perform
enum AdminOperation {
    none,
    /// Reset mutants to unknown
    resetMutant,
    ///
    removeMutant,
    ///
    removeTestCase,
    ///
    markMutant,
}

/// Builtin analyzers for testing frameworks that find failing test cases
enum TestCaseAnalyzeBuiltin {
    /// Tracker for the GoogleTest framework
    gtest,
    /// Tracker for the CTest binary test runner
    ctest,
    /// Tracker for failing makefile targets
    makefile,
}
