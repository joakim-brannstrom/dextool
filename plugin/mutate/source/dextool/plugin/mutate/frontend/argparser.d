/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module is responsible for converting the users CLI arguments to
configuration of how the mutation plugin should behave.
*/
module dextool.plugin.mutate.frontend.argparser;

import core.time : dur;
import logger = std.experimental.logger;
import std.algorithm : joiner, sort, map, filter;
import std.array : empty, array, appender;
import std.exception : collectException;
import std.path : buildPath;
import std.traits : EnumMembers;

import toml : TOMLDocument;

public import dextool.plugin.mutate.backend : Mutation;
public import dextool.plugin.mutate.type;
import dextool.plugin.mutate.config;
import dextool.type : AbsolutePath, Path, ExitStatusType;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

// by default use the recommended operators. These are a good default that test
// those with relatively few equivalent mutants thus most that survive are
// relevant.
private immutable MutationKind[] defaultMutants = [
    MutationKind.lcr, MutationKind.lcrb, MutationKind.sdl, MutationKind.uoi,
    MutationKind.dcr
];

/// Extract and cleanup user input from the command line.
struct ArgParser {
    import std.typecons : Nullable;
    import std.conv : ConvException;
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;

    /// Minimal data needed to bootstrap the configuration.
    MiniConfig miniConf;

    ConfigAdmin admin;
    ConfigAnalyze analyze;
    ConfigCompileDb compileDb;
    ConfigCompiler compiler;
    ConfigMutationTest mutationTest;
    ConfigReport report;
    ConfigWorkArea workArea;
    ConfigGenerate generate;

    struct Data {
        AbsolutePath db;
        ExitStatusType exitStatus = ExitStatusType.Ok;
        MutationKind[] mutation = defaultMutants;
        ToolMode toolMode;
        bool help;
        string[] inFiles;
    }

    Data data;
    alias data this;

    private GetoptResult help_info;

    alias GroupF = void delegate(string[]) @system;
    GroupF[string] groups;

    /// Returns: a config object with default values.
    static ArgParser make() @safe {
        import dextool.compilation_db : defaultCompilerFlagFilter, CompileCommandFilter;

        ArgParser r;
        r.compileDb.flagFilter = CompileCommandFilter(defaultCompilerFlagFilter, 0);
        return r;
    }

    /// Convert the configuration to a TOML file.
    string toTOML() @trusted {
        import std.ascii : newline;
        import std.conv : to;
        import std.format : format;
        import std.parallelism : totalCPUs;
        import std.utf : toUTF8;

        auto app = appender!(string[])();

        app.put("[workarea]");
        app.put(null);
        app.put("# base path (absolute or relative) to look for C/C++ files to mutate.");
        app.put(`root = "."`);
        app.put(null);
        app.put(
                "# files and/or directories (relative to root) to be the **only** sources to mutate.");
        app.put(`restrict = ["."]`);
        app.put(null);

        app.put("[generic]");
        app.put(null);
        app.put("# default mutants to test if none is specified by --mutant");
        app.put(
                "# note that this affects the analyze phase thus the --mutant argument must be one of those specified here");
        app.put(format!"# available options are: [%(%s, %)]"(
                [EnumMembers!MutationKind].map!(a => a.to!string)));
        app.put(format("mutants = [%(%s, %)]", defaultMutants.map!(a => a.to!string)));
        app.put(null);

        app.put("[analyze]");
        app.put(null);
        app.put("# files and/or directories (relative to root) to be excluded from analysis.");
        app.put("# exclude = []");
        app.put(null);
        app.put("# number of threads to be used for analysis (default is the number of cores).");
        app.put(format!"# threads = %s"(totalCPUs));
        app.put(null);
        app.put("# remove files from the database that are no longer found during analysis.");
        app.put(`prune = true`);
        app.put(null);
        app.put("# maximum number of mutants per schema (zero means no limit).");
        app.put(format!"# mutants_per_schema = %s"(analyze.mutantsPerSchema));
        app.put(null);

        app.put("[database]");
        app.put(null);
        app.put("# path (absolute or relative) where mutation statistics will be stored.");
        app.put(`db = "dextool_mutate.sqlite3"`);
        app.put(null);

        app.put("[compiler]");
        app.put(null);
        app.put("# extra flags to pass on to the compiler such as the C++ standard.");
        app.put(format(`# extra_flags = [%(%s, %)]`, compiler.extraFlags));
        app.put(null);
        app.put("# force system includes to use -I instead of -isystem");
        app.put(format!"# force_system_includes = %s"(compiler.forceSystemIncludes));
        app.put(null);
        app.put("# system include paths to use instead of the ones in compile_commands.json");
        app.put(format(`# use_compiler_system_includes = "%s"`, compiler.useCompilerSystemIncludes.length == 0
                ? "/path/to/c++" : compiler.useCompilerSystemIncludes.value));
        app.put(null);

        app.put("[compile_commands]");
        app.put(null);
        app.put("# files and/or directories to look for compile_commands.json.");
        if (compileDb.dbs.length == 0)
            app.put(`search_paths = ["./compile_commands.json"]`);
        else
            app.put(format("search_paths = %s", compileDb.rawDbs));
        app.put(null);
        app.put("# compile flags to remove when analyzing a file.");
        app.put(format("# filter = [%(%s, %)]", compileDb.flagFilter.filter));
        app.put(null);
        app.put("# number of compiler arguments to skip from the beginning (needed when the first argument is NOT a compiler but rather a wrapper).");
        app.put(format("# skip_compiler_args = %s", compileDb.flagFilter.skipCompilerArgs));
        app.put(null);

        app.put("[mutant_test]");
        app.put(null);
        app.put("# command to build the program **and** test suite.");
        app.put(format!`build_cmd = ["cd build && make -j%s"]`(totalCPUs));
        app.put(null);
        app.put("# at least one of test_cmd_dir (recommended) or test_cmd needs to be specified.");
        app.put(null);
        app.put(`# path(s) to recursively look for test binaries to execute.`);
        app.put(`test_cmd_dir = ["./build/test"]`);
        app.put(null);
        app.put(`# flags to add to all executables found in test_cmd_dir.`);
        app.put(`# test_cmd_dir_flag = ["--gtest_filter", "-foo*"]`);
        app.put(null);
        app.put("# command(s) to test the program.");
        app.put("# the arguments for test_cmd can be an array of multiple test commands");
        app.put(`# 1. ["test1.sh", "test2.sh"]`);
        app.put(`# 2. [["test1.sh", "-x"], "test2.sh"]`);
        app.put(`# test_cmd = ["./test.sh"]`);
        app.put(null);
        app.put(
                "# timeout to use for the test suite (by default a measurement-based heuristic will be used).");
        app.put(`# test_cmd_timeout = "1 hours 1 minutes 1 seconds 1 msecs"`);
        app.put(null);
        app.put("# timeout to use when compiling the program and test suite (default: 30 minutes)");
        app.put(`# build_cmd_timeout = "1 hours 1 minutes 1 seconds 1 msecs"`);
        app.put(null);
        app.put(
                "# program used to analyze the output from the test suite for test cases that killed the mutant");
        app.put(`# analyze_cmd = "analyze.sh"`);
        app.put(null);
        app.put("# built-in analyzer of output from testing frameworks to find failing test cases");
        app.put(format("# analyze_using_builtin = [%(%s, %)]",
                [EnumMembers!TestCaseAnalyzeBuiltin].map!(a => a.to!string)));
        app.put(null);
        app.put("# determine in what order mutations are chosen");
        app.put(format("# order = %(%s %)", [EnumMembers!MutationOrder].map!(a => a.to!string)));
        app.put(null);
        app.put("# how to behave when new test cases are found");
        app.put(format("# available options are: %(%s %)",
                [EnumMembers!(ConfigMutationTest.NewTestCases)].map!(a => a.to!string)));
        app.put(`detected_new_test_case = "resetAlive"`);
        app.put(null);
        app.put("# how to behave when test cases are detected as having been removed");
        app.put("# should the test and the gathered statistics be removed too?");
        app.put(format("# available options are: %(%s %)",
                [EnumMembers!(ConfigMutationTest.RemovedTestCases)].map!(a => a.to!string)));
        app.put(`detected_dropped_test_case = "remove"`);
        app.put(null);
        app.put("# how the oldest mutants should be treated.");
        app.put("# It is recommended to test them again.");
        app.put("# Because you may have changed the test suite so mutants that where previously killed by the test suite now survive.");
        app.put(format!"# available options are: %(%s %)"(
                [EnumMembers!(ConfigMutationTest.OldMutant)].map!(a => a.to!string)));
        app.put(`oldest_mutants = "test"`);
        app.put(null);
        app.put("# how many of the oldest mutants to do the above with");
        app.put("# oldest_mutants_nr = 10");
        app.put("# how many of the oldest mutants to do the above with");
        app.put("oldest_mutants_percentage = 1.0");
        app.put(null);
        app.put(
                "# number of threads to be used when running tests in parallel (default is the number of cores).");
        app.put(format!"# parallel_test = %s"(totalCPUs));
        app.put(null);
        app.put("# stop executing tests as soon as a test command fails.");
        app.put(
                "# This speed up the test phase but the report of test cases killing mutants is less accurate");
        app.put("use_early_stop = true");
        app.put(null);
        app.put("# reduce the compile and link time when testing mutants");
        app.put("use_schemata = true");
        app.put(null);
        app.put("# sanity check the schemata before it is used by executing the test cases");
        app.put("# it is a slowdown but nice robustness that is usually worth having");
        app.put("check_schemata = true");
        app.put(null);

        app.put("[report]");
        app.put(null);
        app.put("# default style to use");
        app.put(format("# available options are: %(%s %)",
                [EnumMembers!ReportKind].map!(a => a.to!string)));
        app.put(format(`style = "%s"`, report.reportKind));
        app.put(null);
        app.put("# default report sections when no --section is specified");
        app.put(format!"# available options are: [%(%s, %)]"(
                [EnumMembers!ReportSection].map!(a => a.to!string)));
        app.put(format!"sections = [%(%s, %)]"(report.reportSection.map!(a => a.to!string)));
        app.put(null);

        app.put("[test_group]");
        app.put(null);
        app.put("# subgroups with a description and pattern. Example:");
        app.put("# [test_group.uc1]");
        app.put(`# description = "use case 1"`);
        app.put(`# pattern = "uc_1.*"`);
        app.put(`# see for regex syntax: http://dlang.org/phobos/std_regex.html`);
        app.put(null);

        return app.data.joiner(newline).toUTF8;
    }

    void parse(string[] args) {
        import std.format : format;

        static import std.getopt;

        const db_help = "sqlite3 database to use (default: dextool_mutate.sqlite3)";
        const restrict_help = "restrict mutation to the files in this directory tree (default: .)";
        const out_help = "path used as the root for mutation/reporting of files (default: .)";
        const conf_help = "load configuration (default: .dextool_mutate.toml)";

        // specified by command line. if set it overwride the one from the config.
        MutationKind[] mutants;

        // not used but need to be here. The one used is in MiniConfig.
        string conf_file;
        string db = data.db;

        void analyzerG(string[] args) {
            string[] compile_dbs;
            string[] exclude_files;
            bool noPrune;

            data.toolMode = ToolMode.analyzer;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compile_dbs,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "diff-from-stdin", "restrict testing to the mutants in the diff", &analyze.unifiedDiffFromStdin,
                   "fast-db-store", "improve the write speed of the analyze result (may corrupt the database)", &analyze.fastDbStore,
                   "file-exclude", "exclude files in these directory tree from the analysis (default: none)", &exclude_files,
                   "force-save", "force the result from the analyze to be saved", &analyze.forceSaveAnalyze,
                   "in", "Input file to parse (default: all files in the compilation database)", &data.inFiles,
                   "m|mutant", "kind of mutation save in the database " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutants,
                   "no-prune", "do not prune the database of files that aren't found during the analyze", &noPrune,
                   "out", out_help, &workArea.rawRoot,
                   "profile", "print performance profile for the analyzers that are part of the report", &analyze.profile,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   "schema-mutants", "number of mutants per schema (soft upper limit)", &analyze.mutantsPerSchema,
                   "threads", "number of threads to use for analysing files (default: CPU cores available)", &analyze.poolSize,
                   );
            // dfmt on

            analyze.prune = !noPrune;
            updateCompileDb(compileDb, compile_dbs);
            if (!exclude_files.empty)
                analyze.rawExclude = exclude_files;
        }

        void generateMutantG(string[] args) {
            data.toolMode = ToolMode.generate_mutant;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "out", out_help, &workArea.rawRoot,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   std.getopt.config.required, "id", "mutate the source code as mutant ID", &generate.mutationId,
                   );
            // dfmt on
        }

        void testMutantsG(string[] args) {
            import std.datetime : Clock;

            string[] mutationTester;
            string mutationCompile;
            string[] mutationTestCaseAnalyze;
            long mutationTesterRuntime;
            string maxRuntime;
            string[] testConstraint;
            int maxAlive = -1;

            // set the seed here so if the user specify the CLI the rolling
            // seed is overridden.
            mutationTest.pullRequestSeed += Clock.currTime.isoWeek + Clock.currTime.year;

            data.toolMode = ToolMode.test_mutants;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "L", "restrict testing to the requested files and lines (<file>:<start>-<end>)", &testConstraint,
                   "build-cmd", "program used to build the application", &mutationCompile,
                   "check-schemata", "sanity check a schemata before it is used", &mutationTest.sanityCheckSchemata,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "diff-from-stdin", "restrict testing to the mutants in the diff", &mutationTest.unifiedDiffFromStdin,
                   "dry-run", "do not write data to the filesystem", &mutationTest.dryRun,
                   "load-behavior", "how to behave when the threshold is hit " ~ format("[%(%s|%)]", [EnumMembers!(ConfigMutationTest.LoadBehavior)]), &mutationTest.loadBehavior,
                   "load-threshold", "the 15min loadavg threshold ", mutationTest.loadThreshold.getPtr,
                   "log-schemata", "write the mutation schematas to a separate file", &mutationTest.logSchemata,
                   "max-alive", "stop after NR alive mutants is found (only effective with -L or --diff-from-stdin)", &maxAlive,
                   "max-runtime", format("max time to run the mutation testing for (default: %s)", mutationTest.maxRuntime), &maxRuntime,
                   "m|mutant", "kind of mutation to test " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutants,
                   "only-schemata", "stop testing after the last schema has been executed", &mutationTest.stopAfterLastSchema,
                   "order", "determine in what order mutants are chosen " ~ format("[%(%s|%)]", [EnumMembers!MutationOrder]), &mutationTest.mutationOrder,
                   "out", out_help, &workArea.rawRoot,
                   "pull-request-seed", "seed used when randomly choosing mutants to test in a pull request", &mutationTest.pullRequestSeed,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   "test-case-analyze-builtin", "builtin analyzer of output from testing frameworks to find failing test cases", &mutationTest.mutationTestCaseBuiltin,
                   "test-case-analyze-cmd", "program used to find what test cases killed the mutant", &mutationTestCaseAnalyze,
                   "test-cmd", "program used to run the test suite", &mutationTester,
                   "test-timeout", "timeout to use for the test suite (msecs)", &mutationTesterRuntime,
                   "use-early-stop", "stop executing tests for a mutant as soon as one kill a mutant to speed-up testing", &mutationTest.useEarlyTestCmdStop,
                   "use-schemata", "use schematas to speed-up testing", &mutationTest.useSchemata,
                   );
            // dfmt on

            if (maxAlive > 0)
                mutationTest.maxAlive = maxAlive;
            if (mutationTester.length != 0)
                mutationTest.mutationTester = mutationTester.map!(a => ShellCommand([
                            a
                        ])).array;
            if (mutationCompile.length != 0)
                mutationTest.mutationCompile = ShellCommand([mutationCompile]);
            if (mutationTestCaseAnalyze.length != 0)
                mutationTest.mutationTestCaseAnalyze = mutationTestCaseAnalyze.map!(
                        a => ShellCommand([a])).array;
            if (mutationTesterRuntime != 0)
                mutationTest.mutationTesterRuntime = mutationTesterRuntime.dur!"msecs";
            if (!maxRuntime.empty)
                mutationTest.maxRuntime = parseDuration(maxRuntime);
            mutationTest.constraint = parseUserTestConstraint(testConstraint);
        }

        void reportG(string[] args) {
            string[] compile_dbs;
            string logDir;

            data.toolMode = ToolMode.report;
            ReportSection[] sections;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compile_dbs,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "diff-from-stdin", "report alive mutants in the areas indicated as changed in the diff", &report.unifiedDiff,
                   "logdir", "Directory to write log files to (default: .)", &logDir,
                   "m|mutant", "kind of mutation to report " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutants,
                   "out", out_help, &workArea.rawRoot,
                   "profile", "print performance profile for the analyzers that are part of the report", &report.profile,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   "section", "sections to include in the report " ~ format("[%-(%s|%)]", [EnumMembers!ReportSection]), &sections,
                   "section-tc_stat-num", "number of test cases to report", &report.tcKillSortNum,
                   "section-tc_stat-sort", "sort order when reporting test case kill stat " ~ format("[%(%s|%)]", [EnumMembers!ReportKillSortOrder]), &report.tcKillSortOrder,
                   "style", "kind of report to generate " ~ format("[%(%s|%)]", [EnumMembers!ReportKind]), &report.reportKind,
                   );
            // dfmt on

            if (logDir.empty) {
                logDir = ".";
            }
            report.logDir = logDir.Path.AbsolutePath;
            if (!sections.empty) {
                report.reportSection = sections;
            }

            updateCompileDb(compileDb, compile_dbs);
        }

        void adminG(string[] args) {
            bool dump_conf;
            bool init_conf;
            data.toolMode = ToolMode.admin;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                "c|config", conf_help, &conf_file,
                "db", db_help, &db,
                "dump-config", "dump the detailed configuration used", &dump_conf,
                "init", "create an initial config to use", &init_conf,
                "m|mutant", "mutants to operate on " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutants,
                "mutant-sub-kind", "kind of mutant " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Kind)]), &admin.subKind,
                "operation", "administrative operation to perform " ~ format("[%(%s|%)]", [EnumMembers!AdminOperation]), &admin.adminOp,
                "test-case-regex", "regex to use when removing test cases", &admin.testCaseRegex,
                "status", "change mutants with this state to the value specified by --to-status " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &admin.mutantStatus,
                "to-status", "reset mutants to state (default: unknown) " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &admin.mutantToStatus,
                "id", "specify mutant by Id", &admin.mutationId,
                "rationale", "rationale for marking mutant", &admin.mutantRationale,
                "out", out_help, &workArea.rawRoot,
                );
            // dfmt on

            if (dump_conf)
                data.toolMode = ToolMode.dumpConfig;
            else if (init_conf)
                data.toolMode = ToolMode.initConfig;
        }

        groups["analyze"] = &analyzerG;
        groups["generate"] = &generateMutantG;
        groups["test"] = &testMutantsG;
        groups["report"] = &reportG;
        groups["admin"] = &adminG;

        if (args.length < 2) {
            logger.error("Missing command");
            help = true;
            exitStatus = ExitStatusType.Errors;
            return;
        }

        const string cg = args[1];
        string[] subargs = args[0 .. 1];
        if (args.length > 2)
            subargs ~= args[2 .. $];

        if (auto f = cg in groups) {
            try {
                // trusted: not any external input.
                () @trusted { (*f)(subargs); }();
                help = help_info.helpWanted;
            } catch (std.getopt.GetOptException ex) {
                logger.error(ex.msg);
                help = true;
                exitStatus = ExitStatusType.Errors;
            } catch (Exception ex) {
                logger.error(ex.msg);
                help = true;
                exitStatus = ExitStatusType.Errors;
            }
        } else {
            logger.error("Unknown command: ", cg);
            help = true;
            exitStatus = ExitStatusType.Errors;
            return;
        }

        import std.algorithm : find;
        import std.range : drop;

        if (db.empty) {
            db = "dextool_mutate.sqlite3";
        }
        data.db = AbsolutePath(Path(db));

        if (workArea.rawRoot.empty) {
            workArea.rawRoot = ".";
        }
        workArea.outputDirectory = workArea.rawRoot.Path.AbsolutePath;

        if (workArea.rawRestrict.empty) {
            workArea.rawRestrict = [workArea.rawRoot];
        }
        workArea.restrictDir = workArea.rawRestrict.map!(
                a => AbsolutePath(buildPath(workArea.outputDirectory, a))).array;

        analyze.exclude = analyze.rawExclude.map!(
                a => AbsolutePath(buildPath(workArea.outputDirectory, a))).array;

        if (!mutants.empty) {
            data.mutation = mutants;
        }

        compiler.extraFlags = compiler.extraFlags ~ args.find("--").drop(1).array();
    }

    /**
     * Trusted:
     * The only input is a static string and data derived from getopt itselt.
     * Assuming that getopt in phobos behave well.
     */
    void printHelp() @trusted {
        import std.ascii : newline;
        import std.stdio : writeln;

        string base_help = "Usage: dextool mutate COMMAND [options]";

        switch (toolMode) with (ToolMode) {
        case none:
            writeln("commands: ", newline,
                    groups.byKey.array.sort.map!(a => "  " ~ a).joiner(newline));
            break;
        case analyzer:
            base_help = "Usage: dextool mutate analyze [options] [-- CFLAGS...]";
            break;
        case generate_mutant:
            break;
        case test_mutants:
            logger.infof("--test-case-analyze-builtin possible values: %(%s|%)",
                    [EnumMembers!TestCaseAnalyzeBuiltin]);
            logger.infof(
                    "--max-runtime supported units are [weeks, days, hours, minutes, seconds, msecs]");
            logger.infof(`example: --max-runtime "1 hours 30 minutes"`);
            break;
        case report:
            break;
        case admin:
            break;
        default:
            break;
        }

        defaultGetoptPrinter(base_help, help_info.options);
    }
}

/// Replace the config from the users input.
void updateCompileDb(ref ConfigCompileDb db, string[] compile_dbs) {
    if (compile_dbs.length != 0)
        db.rawDbs = compile_dbs;

    db.dbs = db.rawDbs
        .filter!(a => a.length != 0)
        .map!(a => Path(a).AbsolutePath)
        .array;
}

/** Print a help message conveying how files in the compilation database will
 * be analyzed.
 *
 * It must be enough information that the user can adjust `--out` and `--restrict`.
 */
void printFileAnalyzeHelp(ref ArgParser ap) @safe {
    static void printPath(string user, AbsolutePath real_path) {
        logger.info("  User input: ", user);
        logger.info("  Real path: ", real_path);
    }

    logger.infof("Reading compilation database:\n%-(%s\n%)", ap.compileDb.dbs);

    logger.info(
            "Analyze and mutation of files will only be done on those inside this directory root");
    printPath(ap.workArea.rawRoot, ap.workArea.outputDirectory);
    logger.info(ap.workArea.rawRestrict.length != 0,
            "Restricting mutation to files in the following directory tree(s)");

    assert(ap.workArea.rawRestrict.length == ap.workArea.restrictDir.length);
    foreach (idx; 0 .. ap.workArea.rawRestrict.length) {
        if (ap.workArea.rawRestrict[idx] == ap.workArea.rawRoot)
            continue;
        printPath(ap.workArea.rawRestrict[idx], ap.workArea.restrictDir[idx]);
    }

    logger.info(!ap.analyze.exclude.empty,
            "Excluding files inside the following directory tree(s) from analysis");
    foreach (idx; 0 .. ap.analyze.exclude.length) {
        printPath(ap.analyze.rawExclude[idx], ap.analyze.exclude[idx]);
    }
}

/** Load the configuration from file.
 *
 * Example of a TOML configuration
 * ---
 * [defaults]
 * check_name_standard = true
 * ---
 */
void loadConfig(ref ArgParser rval) @trusted {
    import std.file : exists, readText;
    import toml;

    if (!exists(rval.miniConf.confFile))
        return;

    static auto tryLoading(string configFile) {
        auto txt = readText(configFile);
        auto doc = parseTOML(txt);
        return doc;
    }

    TOMLDocument doc;
    try {
        doc = tryLoading(rval.miniConf.confFile);
    } catch (Exception e) {
        logger.warning("Unable to read the configuration from ", rval.miniConf.confFile);
        logger.warning(e.msg);
        rval.data.exitStatus = ExitStatusType.Errors;
        return;
    }

    rval = loadConfig(rval, doc);
}

ArgParser loadConfig(ArgParser rval, ref TOMLDocument doc) @trusted {
    import std.conv : to;
    import std.path : dirName, buildPath;
    import toml;

    alias Fn = void delegate(ref ArgParser c, ref TOMLValue v);
    Fn[string] callbacks;

    static ShellCommand toShellCommand(ref TOMLValue v, string errorMsg) {
        if (v.type == TOML_TYPE.STRING) {
            return ShellCommand([v.str]);
        } else if (v.type == TOML_TYPE.ARRAY) {
            return ShellCommand(v.array.map!(a => a.str).array);
        }
        logger.warning(errorMsg);
        return ShellCommand.init;
    }

    static ShellCommand[] toShellCommands(ref TOMLValue v, string errorMsg) {
        import std.format : format;

        if (v.type == TOML_TYPE.STRING) {
            return [ShellCommand([v.str])];
        } else if (v.type == TOML_TYPE.ARRAY) {
            return v.array.map!(a => toShellCommand(a,
                    format!"%s: failed to parse as an array"(errorMsg))).array;
        }
        logger.warning(errorMsg);
        return ShellCommand[].init;
    }

    callbacks["analyze.exclude"] = (ref ArgParser c, ref TOMLValue v) {
        c.analyze.rawExclude = v.array.map!(a => a.str).array;
    };
    callbacks["analyze.threads"] = (ref ArgParser c, ref TOMLValue v) {
        c.analyze.poolSize = cast(int) v.integer;
    };
    callbacks["analyze.prune"] = (ref ArgParser c, ref TOMLValue v) {
        c.analyze.prune = v == true;
    };
    callbacks["analyze.mutants_per_schema"] = (ref ArgParser c, ref TOMLValue v) {
        c.analyze.mutantsPerSchema = cast(int) v.integer;
    };

    callbacks["workarea.root"] = (ref ArgParser c, ref TOMLValue v) {
        c.workArea.rawRoot = v.str;
    };
    callbacks["workarea.restrict"] = (ref ArgParser c, ref TOMLValue v) {
        c.workArea.rawRestrict = v.array.map!(a => a.str).array;
    };

    callbacks["generic.mutants"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.mutation = v.array.map!(a => a.str.to!MutationKind).array;
        } catch (Exception e) {
            logger.info("Available mutation kinds ", [EnumMembers!MutationKind]);
            logger.error(e.msg);
        }
    };

    callbacks["database.db"] = (ref ArgParser c, ref TOMLValue v) {
        c.db = v.str.Path.AbsolutePath;
    };

    callbacks["compile_commands.search_paths"] = (ref ArgParser c, ref TOMLValue v) {
        c.compileDb.rawDbs = v.array.map!"a.str".array;
    };
    callbacks["compile_commands.filter"] = (ref ArgParser c, ref TOMLValue v) {
        import dextool.type : FilterClangFlag;

        c.compileDb.flagFilter.filter = v.array.map!(a => FilterClangFlag(a.str)).array;
    };
    callbacks["compile_commands.skip_compiler_args"] = (ref ArgParser c, ref TOMLValue v) {
        c.compileDb.flagFilter.skipCompilerArgs = cast(int) v.integer;
    };

    callbacks["compiler.extra_flags"] = (ref ArgParser c, ref TOMLValue v) {
        c.compiler.extraFlags = v.array.map!(a => a.str).array;
    };
    callbacks["compiler.force_system_includes"] = (ref ArgParser c, ref TOMLValue v) {
        c.compiler.forceSystemIncludes = v == true;
    };
    callbacks["compiler.use_compiler_system_includes"] = (ref ArgParser c, ref TOMLValue v) {
        c.compiler.useCompilerSystemIncludes = v.str;
    };

    callbacks["mutant_test.test_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTester = toShellCommands(v,
                "config: failed to parse mutant_test.test_cmd");
    };
    callbacks["mutant_test.test_cmd_dir"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.testCommandDir = v.array.map!(a => Path(a.str)).array;
    };
    callbacks["mutant_test.test_cmd_dir_flag"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.testCommandDirFlag = v.array.map!(a => a.str).array;
    };
    callbacks["mutant_test.test_cmd_timeout"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTesterRuntime = v.str.parseDuration;
    };
    callbacks["mutant_test.build_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationCompile = toShellCommand(v,
                "config: failed to parse mutant_test.build_cmd");
    };
    callbacks["mutant_test.build_cmd_timeout"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.buildCmdTimeout = v.str.parseDuration;
    };
    callbacks["mutant_test.analyze_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTestCaseAnalyze = toShellCommands(v,
                "config: failed to parse mutant_test.analyze_cmd");
    };
    callbacks["mutant_test.analyze_using_builtin"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTestCaseBuiltin = v.array.map!(
                a => a.str.to!TestCaseAnalyzeBuiltin).array;
    };
    callbacks["mutant_test.order"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationOrder = v.str.to!MutationOrder;
    };
    callbacks["mutant_test.detected_new_test_case"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.mutationTest.onNewTestCases = v.str.to!(ConfigMutationTest.NewTestCases);
        } catch (Exception e) {
            logger.info("Available alternatives: ",
                    [EnumMembers!(ConfigMutationTest.NewTestCases)]);
            logger.error(e.msg);
        }
    };
    callbacks["mutant_test.detected_dropped_test_case"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.mutationTest.onRemovedTestCases = v.str.to!(ConfigMutationTest.RemovedTestCases);
        } catch (Exception e) {
            logger.info("Available alternatives: ",
                    [EnumMembers!(ConfigMutationTest.RemovedTestCases)]);
            logger.error(e.msg);
        }
    };
    callbacks["mutant_test.oldest_mutants"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.mutationTest.onOldMutants = v.str.to!(ConfigMutationTest.OldMutant);
        } catch (Exception e) {
            logger.info("Available alternatives: ", [
                    EnumMembers!(ConfigMutationTest.OldMutant)
                    ]);
            logger.error(e.msg);
        }
    };
    callbacks["mutant_test.oldest_mutants_nr"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.oldMutantsNr = v.integer;
    };
    callbacks["mutant_test.oldest_mutants_percentage"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.oldMutantPercentage.get = v.floating;
    };
    callbacks["mutant_test.parallel_test"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.testPoolSize = cast(int) v.integer;
    };
    callbacks["mutant_test.use_early_stop"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.useEarlyTestCmdStop = v == true;
    };
    callbacks["mutant_test.use_schemata"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.useSchemata = v == true;
    };
    callbacks["mutant_test.check_schemata"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.sanityCheckSchemata = v == true;
    };

    callbacks["report.style"] = (ref ArgParser c, ref TOMLValue v) {
        c.report.reportKind = v.str.to!ReportKind;
    };
    callbacks["report.sections"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.report.reportSection = v.array.map!(a => a.str.to!ReportSection).array;
        } catch (Exception e) {
            logger.info("Available mutation kinds ", [
                    EnumMembers!ReportSection
                    ]);
            logger.error(e.msg);
        }
    };

    void iterSection(ref ArgParser c, string sectionName) {
        if (auto section = sectionName in doc) {
            // specific configuration from section members
            foreach (k, v; *section) {
                if (auto cb = (sectionName ~ "." ~ k) in callbacks) {
                    try {
                        (*cb)(c, v);
                    } catch (Exception e) {
                        logger.error(e.msg).collectException;
                    }
                } else {
                    logger.infof("Unknown key '%s' in configuration section '%s'", k, sectionName);
                }
            }
        }
    }

    iterSection(rval, "generic");
    iterSection(rval, "analyze");
    iterSection(rval, "workarea");
    iterSection(rval, "database");
    iterSection(rval, "compiler");
    iterSection(rval, "compile_commands");
    iterSection(rval, "mutant_test");
    iterSection(rval, "report");

    parseTestGroups(rval, doc);

    return rval;
}

void parseTestGroups(ref ArgParser c, ref TOMLDocument doc) @trusted {
    import toml;

    if ("test_group" !in doc)
        return;

    foreach (k, s; *("test_group" in doc)) {
        if (s.type != TOML_TYPE.TABLE)
            continue;

        string desc;
        if (auto v = "description" in s)
            desc = v.str;
        if (auto v = "pattern" in s) {
            string re = v.str;
            c.report.testGroups ~= TestGroup(k, desc, re);
        }
    }
}

@("shall populate the test, build and analyze command of an ArgParser from a TOML document")
@system unittest {
    import std.format : format;
    import toml : parseTOML;

    immutable txt = `
[mutant_test]
test_cmd = %s
build_cmd = %s
analyze_cmd = %s
`;

    {
        auto doc = parseTOML(format!txt(`"test.sh"`, `"build.sh"`, `"analyze.sh"`));
        auto ap = loadConfig(ArgParser.init, doc);
        ap.mutationTest.mutationTester.shouldEqual([ShellCommand(["test.sh"])]);
        ap.mutationTest.mutationCompile.shouldEqual(ShellCommand(["build.sh"]));
        ap.mutationTest.mutationTestCaseAnalyze.shouldEqual([
                ShellCommand(["analyze.sh"])
                ]);
    }

    {
        auto doc = parseTOML(format!txt(`[["test1.sh"], ["test2.sh"]]`,
                `["build.sh", "-y"]`, `[["analyze.sh", "-z"]]`));
        auto ap = loadConfig(ArgParser.init, doc);
        ap.mutationTest.mutationTester.shouldEqual([
                ShellCommand(["test1.sh"]), ShellCommand(["test2.sh"])
                ]);
        ap.mutationTest.mutationCompile.shouldEqual(ShellCommand([
                    "build.sh", "-y"
                ]));
        ap.mutationTest.mutationTestCaseAnalyze.shouldEqual([
                ShellCommand(["analyze.sh", "-z"])
                ]);
    }

    {
        auto doc = parseTOML(format!txt(`[["test1.sh", "-x"], ["test2.sh", "-y"]]`,
                `"build.sh"`, `"analyze.sh"`));
        auto ap = loadConfig(ArgParser.init, doc);
        ap.mutationTest.mutationTester.shouldEqual([
                ShellCommand(["test1.sh", "-x"]), ShellCommand([
                        "test2.sh", "-y"
                    ])
                ]);
    }
}

@("shall set the thread analyze limitation from the configuration")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[analyze]
threads = 42
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.analyze.poolSize.shouldEqual(42);
}

@("shall set how many tests are executed in parallel from the configuration")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[mutant_test]
parallel_test = 42
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.mutationTest.testPoolSize.shouldEqual(42);
}

@("shall deactivate prune of old files when analyze")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[analyze]
prune = false
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.analyze.prune.shouldBeFalse;
}

@("shall activate early stop of test commands")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[mutant_test]
use_early_stop = true
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.mutationTest.useEarlyTestCmdStop.shouldBeTrue;
}

@("shall activate schematas and sanity check of schematas")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[mutant_test]
use_schemata = true
check_schemata = true
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.mutationTest.useSchemata.shouldBeTrue;
    ap.mutationTest.sanityCheckSchemata.shouldBeTrue;
}

@("shall set the number of mutants per schema")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[analyze]
mutants_per_schema = 200
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.analyze.mutantsPerSchema.shouldEqual(200);
}

@("shall parse the build command timeout")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[mutant_test]
build_cmd_timeout = "1 hours"
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.mutationTest.buildCmdTimeout.shouldEqual(1.dur!"hours");
}

@("shall parse the mutants to test")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[generic]
mutants = ["lcr"]
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.data.mutation.shouldEqual([MutationKind.lcr]);
}

@("shall parse the report sections")
@system unittest {
    import toml : parseTOML;

    immutable txt = `
[report]
sections = ["all_mut", "summary"]
`;
    auto doc = parseTOML(txt);
    auto ap = loadConfig(ArgParser.init, doc);
    ap.report.reportSection.shouldEqual([
            ReportSection.all_mut, ReportSection.summary
            ]);
}

/// Minimal config to setup path to config file.
struct MiniConfig {
    /// Value from the user via CLI, unmodified.
    string rawConfFile;

    /// The configuration file that has been loaded
    AbsolutePath confFile;

    bool shortPluginHelp;
}

/// Returns: minimal config to load settings and setup working directory.
MiniConfig cliToMiniConfig(string[] args) @trusted nothrow {
    import std.file : exists;
    static import std.getopt;

    immutable default_conf = ".dextool_mutate.toml";

    MiniConfig conf;

    try {
        std.getopt.getopt(args, std.getopt.config.keepEndOfOptions, std.getopt.config.passThrough,
                "c|config", "none not visible to the user", &conf.rawConfFile,
                "short-plugin-help", "not visible to the user", &conf.shortPluginHelp);
        if (conf.rawConfFile.length == 0)
            conf.rawConfFile = default_conf;
        conf.confFile = Path(conf.rawConfFile).AbsolutePath;
    } catch (Exception e) {
        logger.trace(conf).collectException;
        logger.error(e.msg).collectException;
    }

    return conf;
}

auto parseDuration(string timeSpec) {
    import std.conv : to;
    import std.string : split;
    import std.datetime : Duration, dur;
    import std.range : chunks;

    Duration d;
    const parts = timeSpec.split;

    if (parts.length % 2 != 0) {
        logger.warning("Invalid time specification because either the number or unit is missing");
        return d;
    }

    foreach (const p; parts.chunks(2)) {
        const nr = p[0].to!long;
        bool validUnit;
        immutable Units = [
            "msecs", "seconds", "minutes", "hours", "days", "weeks"
        ];
        static foreach (Unit; Units) {
            if (p[1] == Unit) {
                d += nr.dur!Unit;
                validUnit = true;
            }
        }
        if (!validUnit) {
            logger.warningf("Invalid unit '%s'. Valid are %-(%s, %).", p[1], Units);
            return d;
        }
    }

    return d;
}

@("shall parse a string to a duration")
unittest {
    const expected = 1.dur!"weeks" + 1.dur!"days" + 3.dur!"hours"
        + 2.dur!"minutes" + 5.dur!"seconds" + 9.dur!"msecs";
    const d = parseDuration("1 weeks 1 days 3 hours 2 minutes 5 seconds 9 msecs");
    d.should == expected;
}

auto parseUserTestConstraint(string[] raw) {
    import std.conv : to;
    import std.regex : regex, matchFirst;
    import std.typecons : tuple;
    import dextool.plugin.mutate.type : TestConstraint;

    TestConstraint rval;
    const re = regex(`(?P<file>.*):(?P<start>\d*)-(?P<end>\d*)`);

    foreach (r; raw.map!(a => tuple!("user", "match")(a, matchFirst(a, re)))) {
        if (r.match.empty) {
            logger.warning("Unable to parse ", r.user);
            continue;
        }

        const start = r.match["start"].to!uint;
        const end = r.match["end"].to!uint + 1;

        if (start > end) {
            logger.warningf("Unable to parse %s because start (%s) must be less than end (%s)",
                    r.user, r.match["start"], r.match["end"]);
            continue;
        }

        foreach (const l; start .. end)
            rval.value[Path(r.match["file"])] ~= Line(l);
    }

    return rval;
}

@("shall parse a test restriction")
unittest {
    const r = parseUserTestConstraint([
            "foo/bar:1-10", "smurf bar/i oknen:ea,ting:33-45"
            ]);

    Path("foo/bar").shouldBeIn(r.value);
    r.value[Path("foo/bar")][0].should == Line(1);
    r.value[Path("foo/bar")][9].should == Line(10);

    Path("smurf bar/i oknen:ea,ting").shouldBeIn(r.value);
    r.value[Path("smurf bar/i oknen:ea,ting")][0].should == Line(33);
    r.value[Path("smurf bar/i oknen:ea,ting")][12].should == Line(45);
}
