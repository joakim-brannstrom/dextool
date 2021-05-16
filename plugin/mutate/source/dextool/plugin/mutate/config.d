/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.config;

import core.time : Duration, dur;
import std.typecons : Nullable;

import my.filter : GlobFilter;
import my.named_type;
import my.optional;

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
    ReportSection[] reportSection = [ReportSection.summary];

    /// Directory to write logs to when writing to the filesystem.
    AbsolutePath logDir;

    /// Controls how to sort test cases by their kill statistics.
    ReportKillSortOrder tcKillSortOrder;
    int tcKillSortNum = 20;

    /// User regex for reporting groups of tests
    TestGroup[] testGroups;

    /// If a unified diff should be used in the report
    bool unifiedDiff;

    /// If profiling data should be printed.
    bool profile;

    NamedType!(uint, Tag!"HighInterestMutantsNr", uint.init, TagStringable) highInterestMutantsNr = 5;
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

/// Configuration of how the mutation analyzer should act.
struct ConfigAnalyze {
    /// User input of excludes before they are adjusted to relative root
    string[] rawExclude;
    /// User input of includes before they are adjusted to relative root
    string[] rawInclude;

    /// The constructed glob filter which based on rawExclude and rawinclude.
    GlobFilter fileMatcher;

    /// The size of the thread pool which affects how many files are analyzed in parallel.
    int poolSize;

    /// What files to analyze is derived from a diff.
    bool unifiedDiffFromStdin;

    /// Remove files from the database that aren't found when analyzing.
    bool prune;

    /// Turn off the sqlite synchronization safety
    bool fastDbStore;

    /// If profiling data should be printed.
    bool profile;

    /// Force the result from the files to always be saved
    bool forceSaveAnalyze;

    /// Number of mutants to at most put in a schema (soft limit)
    NamedType!(long, Tag!"MutantsPerSchema", long.init, TagStringable) mutantsPerSchema = 1000;

    /// Minimum number of mutants per schema for the schema to be saved in the database.
    NamedType!(long, Tag!"MinMutantsPerSchema", long.init, TagStringable) minMutantsPerSchema = 3;

    /// User file/directories containing tests to checksum and timestamp
    string[] rawTestPaths;
    AbsolutePath[] testPaths;

    /// User input of excludes before they are adjusted to relative root
    string[] rawTestExclude;
    /// User input of includes before they are adjusted to relative root
    string[] rawTestInclude;

    /// The constructed glob filter which based on rawExclude and rawinclude.
    GlobFilter testFileMatcher;

    /// If coverage maps should be generated and saved.
    NamedType!(bool, Tag!"SaveCoverage", bool.init, TagStringable) saveCoverage;
}

/// Settings for the compiler
struct ConfigCompiler {
    import dextool.compilation_db : SystemCompiler = Compiler;

    /// Additional flags the user wants to add besides those that are in the compile_commands.json.
    string[] extraFlags;

    /// True requires system includes to be passed on to the compiler via -I
    bool forceSystemIncludes;

    /// Deduce compiler flags from this compiler and not the one in the
    /// supplied compilation database.  / This is needed when the one specified
    /// in the DB has e.g. a c++ stdlib that is not compatible with clang.
    SystemCompiler useCompilerSystemIncludes;

    NamedType!(bool, Tag!"AllowErrors", bool.init, TagStringable) allowErrors;
}

/// Settings for mutation testing
struct ConfigMutationTest {
    ShellCommand[] mutationTester;
    /// Find executables in this directory and add them to mutationTester.
    Path[] testCommandDir;
    /// Flags to add to all executables found in `testCommandDir`
    string[] testCommandDirFlag;

    ShellCommand mutationCompile;
    ShellCommand[] mutationTestCaseAnalyze;
    TestCaseAnalyzeBuiltin[] mutationTestCaseBuiltin;

    /// If the user hard code a timeout for the test suite.
    Nullable!Duration mutationTesterRuntime;

    /// Timeout to use when compiling.
    Duration buildCmdTimeout = 30.dur!"minutes";

    /// In what order to choose mutants to test.
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
    NamedType!(double, Tag!"OldMutantPercentage", double.init, TagStringable) oldMutantPercentage = 0.0;

    /// Max time to run mutation testing.
    // note that Duration.max + Clock.currTime results in a negative time...
    Duration maxRuntime = 52.dur!"weeks";

    // Constrain the mutation testing.
    TestConstraint constraint;

    /// If constraints should be read from a unified diff via stdin.
    bool unifiedDiffFromStdin;

    /// Stop after this many alive mutants are found. Only effective if constraint.empty is false.
    Nullable!int maxAlive;

    /// The size of the thread pool which affects how many tests are executed in parallel.
    int testPoolSize;

    /// Seed used when randomly choosing mutants to test in a pull request.
    long pullRequestSeed = 42;

    /// If early stopping of test command execution should be used
    bool useEarlyTestCmdStop;

    /// If schematas are used for mutation testing.
    bool useSchemata;

    /// Sanity check a schemata before it is used.
    bool sanityCheckSchemata;

    /// If the schematas should be written to a separate file for offline inspection.
    bool logSchemata;

    /// Stop mutation testing after the last schemata has been executed
    bool stopAfterLastSchema;

    /// Minimum number of mutants per schema for it to be used.
    NamedType!(long, Tag!"MinMutantsPerSchema", long.init, TagStringable) minMutantsPerSchema = 3;

    enum LoadBehavior {
        nothing,
        /// Slow the testing until the load goes below the threshold
        slowdown,
        /// Stop mutation testing if the 15min load average reach this number.
        halt,
    }

    LoadBehavior loadBehavior;
    NamedType!(double, Tag!"LoadThreshold", double.init, TagStringable) loadThreshold;

    /// If coverage data should be gathered and saved.
    NamedType!(bool, Tag!"UseCoverage", bool.init, TagStringable) useCoverage;

    /// If the generated coverage files should be saved.
    NamedType!(bool, Tag!"LogCoverage", bool.init, TagStringable) logCoverage;

    /// allows a user to control exactly which files the coverage and schemata runtime is injected in.
    UserRuntime[] userRuntimeCtrl;

    /// Continuesly run the test suite to see that the test suite is OK when no mutants are injected.
    NamedType!(bool, Tag!"ContinuesCheckTestSuite", bool.init, TagStringable) contCheckTestSuite;
    NamedType!(int, Tag!"ContinuesCheckTestSuitePeriod", int.init, TagStringable) contCheckTestSuitePeriod = 100;

    NamedType!(bool, Tag!"TestCmdChecksum", bool.init, TagStringable) testCmdChecksum;

    NamedType!(long, Tag!"MaxTestCaseOutputCaptureMbyte", int.init, TagStringable) maxTestCaseOutput = 10;
}

/// Settings for the administration mode
struct ConfigAdmin {
    AdminOperation adminOp;
    Mutation.Status mutantStatus;
    Mutation.Status mutantToStatus;
    string testCaseRegex;
    long mutationId;
    string mutantRationale;

    /// used to specify a kind of mutation
    Mutation.Kind[] subKind;
}

struct ConfigWorkArea {
    /// User input root.
    string rawRoot;

    AbsolutePath root;

    /// User input of excludes before they are adjusted to relative root
    string[] rawExclude;
    /// User input of includes before they are adjusted to relative root
    string[] rawInclude;

    /// The constructed glob filter which based on rawExclude and rawinclude.
    /// Only mutants whose location match will be generated.
    GlobFilter mutantMatcher;
}

/// Configuration of the generate mode.
struct ConfigGenerate {
    long mutationId;
}
