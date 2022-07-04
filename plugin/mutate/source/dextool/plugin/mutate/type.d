/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.type;

import dextool.type : Path, AbsolutePath;

/// The kind of mutation to perform
enum MutationKind {
    /// all mutation operators are used
    all,
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
    /// Statement deletion
    sdl,
    /// Decision/Condition Requirement
    dcr,
    /// Logical Connector Replacement Bit-wise
    lcrb,
    /// rithmetic operator replacement simple
    aors,
    /// constant replacement
    cr,
}

/// The order the mutations are done when running in test_mutants mode
enum MutationOrder {
    random,
    consecutive,
    bySize,
}

/// The kind of report to generate to the user
enum ReportKind {
    /// As a plain text output
    plain,
    /// As compiler warnings and a fix-it hint for the mutation
    compiler,
    /// As a JSON model
    json,
    /// As a HTML report
    html,
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
    /// mutants that has survived that the plugin recommend the user to kill
    mut_recommend_kill,
    /// a section containing a diff and mutants for it
    diff,
    /// report of the mutants that only the test case kill
    tc_unique,
    /// mutants manually marked by user
    marked_mutants,
    /// trend information of how mutation score is predicted to evolve
    trend,
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
    ///
    removeMarkedMutant,
    ///
    resetTestCase,
    /// compact the database to reduce the disc space it takes up
    compact,
    /// force a mutation testing to stop testing timeout mutants
    stopTimeoutTest,
    /// Reset all mutants of a kind
    resetMutantSubKind,
    /// reset the worklist of mutants to test
    clearWorklist,
}

/// Builtin analyzers for testing frameworks that find failing test cases
enum TestCaseAnalyzeBuiltin {
    /// Tracker for the GoogleTest framework
    gtest,
    /// Tracker for the CTest binary test runner
    ctest,
    /// Tracker for failing makefile targets
    makefile,
    /// Only track the test_cmd
    test_cmd
}

/// A line in a file.
struct Line {
    uint value;
}

/// A constraint for what to mutate during the test phase..
struct TestConstraint {
    Line[][Path] value;

    bool empty() @safe pure nothrow const @nogc {
        return value.length == 0;
    }
}

struct ShellCommand {
    import std.algorithm : joiner;
    import std.array : appender;
    import std.format : formattedWrite;
    import std.path : relativePath;
    import std.range : isOutputRange, only;
    import std.string : join;

    string[] value;

    bool empty() @safe pure nothrow const @nogc {
        return value.length == 0;
    }

    string toString() @safe pure const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        formattedWrite(w, "shell command '%-(%s %)'", value);
    }

    string toShortString() @safe nothrow const {
        auto r = () nothrow{
            try {
                return value[0].relativePath;
            } catch (Exception e) {
            }
            return value[0];
        }();
        if (value.length == 1)
            return r;
        return only([r], value[1 .. $]).joiner.join(" ");
    }
}

struct UserRuntime {
    import dextool.plugin.mutate.backend.type : Language;

    Path file;
    Language lang;
}

enum SchemaRuntime : ubyte {
    inject,
    library,
}

enum CoverageRuntime : ubyte {
    inject,
    library,
}

enum MutantIdGeneratorConfig : ubyte {
    relaxed,
    strict,
}
