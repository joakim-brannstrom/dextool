/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.config;

import core.time : Duration;
import std.typecons : Nullable;

import dextool.plugin.mutate.type;
import dextool.type : AbsolutePath, Path;
public import dextool.plugin.mutate.backend : Mutation, TestGroup;

/// The mode the tool is operating in
enum ToolMode {
    /// No mode set
    none,
    /// analyze for mutation points
    analyzer,
    /// center that can operate and control subcomponents
    generate_mutant,
    /// test mutation points with a test suite
    test_mutants,
    /// generate a report of the mutation points
    report,
    /// administrator interface for the mutation database
    admin,
    /// Dump the TOML configuration to the console
    dumpConfig,
    /// Write a TOML config to the filesystem
    initConfig,
}

/// Config of the report.
struct ConfigReport {
    ReportKind reportKind;
    ReportLevel reportLevel;
    ReportSection[] reportSection;

    /// Directory to write logs to when writing to the filesystem.
    AbsolutePath logDir;

    /// Controls how to sort test cases by their kill statistics.
    ReportKillSortOrder tcKillSortOrder;
    int tcKillSortNum = 20;

    /// User regex for reporting groups of tests
    TestGroup[] testGroups;

    /// If a unified diff should be used in the report
    bool unifiedDiff;
}

/// Configuration data for the compile_commands.json
struct ConfigCompileDb {
    import dextool.compilation_db : CompileCommandFilter;

    /// Raw user input via either config or cli
    string[] rawDbs;

    /// path to compilation databases.
    AbsolutePath[] dbs;

    /// Flags the user wants to be automatically removed from the compile_commands.json.
    CompileCommandFilter flagFilter;
}

/// Settings for the compiler
struct ConfigCompiler {
    /// Additional flags the user wants to add besides those that are in the compile_commands.json.
    string[] extraFlags;

    /// True requires system includes to be passed on to the compiler via -I
    bool forceSystemIncludes;
}

/// Settings for mutation testing
struct ConfigMutationTest {
    AbsolutePath mutationTester;
    AbsolutePath mutationCompile;
    AbsolutePath mutationTestCaseAnalyze;
    TestCaseAnalyzeBuiltin[] mutationTestCaseBuiltin;
    Nullable!Duration mutationTesterRuntime;
    MutationOrder mutationOrder;
    bool dryRun;

    /// How to behave when new test cases are detected.
    enum NewTestCases {
        doNothing,
        /// Automatically reset alive mutants
        resetAlive,
    }

    NewTestCases onNewTestCases;

    /// How to behave when test cases are detected of having been removed
    enum RemovedTestCases {
        doNothing,
        /// Remove it and all results connectedto the test case
        remove,
    }

    RemovedTestCases onRemovedTestCases;

    /// How to behave when mutants have aged.
    enum OldMutant {
        nothing,
        test,
    }

    OldMutant onOldMutants;
    long oldMutantsNr;
}

/// Settings for the administration mode
struct ConfigAdmin {
    AdminOperation adminOp;
    Mutation.Status mutantStatus;
    Mutation.Status mutantToStatus;
    string testCaseRegex;
}

struct ConfigWorkArea {
    /// User input root.
    string rawRoot;
    string[] rawRestrict;

    AbsolutePath outputDirectory;
    AbsolutePath[] restrictDir;
}
