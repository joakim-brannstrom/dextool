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
import std.traits : EnumMembers;

import toml : TOMLDocument;

public import dextool.plugin.mutate.backend : Mutation;
public import dextool.plugin.mutate.type;
import dextool.plugin.mutate.config;
import dextool.utility : asAbsNormPath;
import dextool.type : AbsolutePath, Path, ExitStatusType, ShellCommand;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

/// Extract and cleanup user input from the command line.
struct ArgParser {
    import std.typecons : Nullable;
    import std.conv : ConvException;
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;
    import dextool.type : FileName;

    /// Minimal data needed to bootstrap the configuration.
    MiniConfig miniConf;

    ConfigAdmin admin;
    ConfigAnalyze analyze;
    ConfigCompileDb compileDb;
    ConfigCompiler compiler;
    ConfigMutationTest mutationTest;
    ConfigReport report;
    ConfigWorkArea workArea;

    struct Data {
        string[] inFiles;

        AbsolutePath db;

        bool help;
        ExitStatusType exitStatus = ExitStatusType.Ok;

        MutationKind[] mutation;

        Nullable!long mutationId;

        ToolMode toolMode;

        Mutation.Status to_status;
        ulong mutant_id;
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
        import std.utf : toUTF8;

        auto app = appender!(string[])();

        app.put("[workarea]");
        app.put("# path used as the root for accessing files");
        app.put(
                "# dextool will not modify files with a path outside the root when it perform mutation testing");
        app.put(`# root = "."`);
        app.put("# restrict analysis to files in this directory tree");
        app.put("# this make it possible to only mutate certain parts of an application");
        app.put("# use relative paths that are inside the root");
        app.put("# restrict = []");
        app.put(null);

        app.put("[analyze]");
        app.put("# exclude files in these directory tree(s) from analysis");
        app.put("# relative paths are relative to the directory dextool is executed in");
        app.put("# exclude = []");
        app.put(null);

        app.put("[database]");
        app.put("# path to where to store the sqlite3 database");
        app.put(`# db = "dextool_mutate.sqlite3"`);
        app.put(null);

        app.put("[compiler]");
        app.put("# extra flags to pass on to the compiler such as the C++ standard");
        app.put(format(`# extra_flags = [%(%s, %)]`, compiler.extraFlags));
        app.put("# toggle this to force system include paths to use -I instead of -isystem");
        app.put("# force_system_includes = true");
        app.put(
                "# use this compilers system includes instead of the one used in the compile_commands.json");
        app.put(format(`# use_compiler_system_includes = "%s"`, compiler.useCompilerSystemIncludes.length == 0
                ? "/path/to/c++" : compiler.useCompilerSystemIncludes.value));
        app.put(null);

        app.put("[compile_commands]");
        app.put("# search for compile_commands.json in this paths");
        if (compileDb.dbs.length == 0)
            app.put(`# search_paths = ["./compile_commands.json"]`);
        else
            app.put(format("search_paths = %s", compileDb.rawDbs));
        app.put("# flags to remove when analyzing a file in the DB");
        app.put(format("# filter = [%(%s, %)]", compileDb.flagFilter.filter));
        app.put("# compiler arguments to skip from the beginning. Needed when the first argument is NOT a compiler but rather a wrapper");
        app.put(format("# skip_compiler_args = %s", compileDb.flagFilter.skipCompilerArgs));
        app.put(null);

        app.put("[mutant_test]");
        app.put("# (required) program used to run the test suite");
        app.put(`test_cmd = "test.sh"`);
        app.put("# timeout to use for the test suite (msecs)");
        app.put("# test_cmd_timeout = 1000");
        app.put("# (required) program used to build the application");
        app.put(`build_cmd = "build.sh"`);
        app.put(
                "# program used to analyze the output from the test suite for test cases that killed the mutant");
        app.put(`# analyze_cmd = "analyze.sh"`);
        app.put("# builtin analyzer of output from testing frameworks to find failing test cases");
        app.put(format("# analyze_using_builtin = [%(%s, %)]",
                [EnumMembers!TestCaseAnalyzeBuiltin].map!(a => a.to!string)));
        app.put("# determine in what order mutations are chosen");
        app.put(format("# order = %(%s|%)", [EnumMembers!MutationOrder].map!(a => a.to!string)));
        app.put("# how to behave when new test cases are found");
        app.put(format("# detected_new_test_case = %(%s|%)",
                [EnumMembers!(ConfigMutationTest.NewTestCases)].map!(a => a.to!string)));
        app.put("# how to behave when test cases are detected as having been removed");
        app.put("# should the test and the gathered statistics be remove too?");
        app.put(format("# detected_dropped_test_case = %(%s|%)",
                [EnumMembers!(ConfigMutationTest.RemovedTestCases)].map!(a => a.to!string)));
        app.put("# how the oldest mutants should be treated.");
        app.put("# It is recommended to test them again.");
        app.put("# Because you may have changed the test suite so mutants that where previously killed by the test suite now survive.");
        app.put(format("# oldest_mutants = %(%s|%)",
                [EnumMembers!(ConfigMutationTest.OldMutant)].map!(a => a.to!string)));
        app.put("# How many of the oldest mutants to do the above with");
        app.put("# oldest_mutants_nr = 10");
        app.put(null);

        app.put("[report]");
        app.put("# default style to use");
        app.put(format("# style = %(%s|%)", [EnumMembers!ReportKind].map!(a => a.to!string)));
        app.put(null);

        app.put("[test_group]");
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

        // not used but need to be here. The one used is in MiniConfig.
        string conf_file;
        string db;
	string mut_id_string;

        void analyzerG(string[] args) {
            string[] compile_dbs;
            string[] exclude_files;

            data.toolMode = ToolMode.analyzer;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compile_dbs,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "in", "Input file to parse (default: all files in the compilation database)", &data.inFiles,
                   "out", out_help, &workArea.rawRoot,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   "file-exclude", "exclude files in these directory tree from the analysis (default: none)", &exclude_files,
                   );
            // dfmt on

            updateCompileDb(compileDb, compile_dbs);
            if (!exclude_files.empty)
                analyze.exclude = exclude_files.map!(a => a.Path.AbsolutePath).array;
        }

        void generateMutantG(string[] args) {
            data.toolMode = ToolMode.generate_mutant;
            string cli_mutation_id;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "out", out_help, &workArea.rawRoot,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   "id", "mutate the source code as mutant ID", &cli_mutation_id,
                   );
            // dfmt on

            try {
                import std.conv : to;

                if (cli_mutation_id.length != 0)
                    data.mutationId = cli_mutation_id.to!long;
            } catch (ConvException e) {
                logger.infof("Invalid mutation point '%s'. It must be in the range [0, %s]",
                        cli_mutation_id, long.max);
            }
        }

        void testMutantsG(string[] args) {
            string mutationTester;
            string mutationCompile;
            string mutationTestCaseAnalyze;
            long mutationTesterRuntime;
            string maxRuntime;

            data.toolMode = ToolMode.test_mutants;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "build-cmd", "program used to build the application", &mutationCompile,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "dry-run", "do not write data to the filesystem", &mutationTest.dryRun,
                   "mutant", "kind of mutation to test " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                   "order", "determine in what order mutations are chosen " ~ format("[%(%s|%)]", [EnumMembers!MutationOrder]), &mutationTest.mutationOrder,
                   "out", out_help, &workArea.rawRoot,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   "test-cmd", "program used to run the test suite", &mutationTester,
                   "test-case-analyze-builtin", "builtin analyzer of output from testing frameworks to find failing test cases", &mutationTest.mutationTestCaseBuiltin,
                   "test-case-analyze-cmd", "program used to find what test cases killed the mutant", &mutationTestCaseAnalyze,
                   "test-timeout", "timeout to use for the test suite (msecs)", &mutationTesterRuntime,
                   "max-runtime", format("max time to run the mutation testing for (default: %s)", mutationTest.maxRuntime), &maxRuntime,
                   );
            // dfmt on

            if (mutationTester.length != 0)
                mutationTest.mutationTester = ShellCommand(mutationTester);
            if (mutationCompile.length != 0)
                mutationTest.mutationCompile = ShellCommand(mutationCompile);
            if (mutationTestCaseAnalyze.length != 0)
                mutationTest.mutationTestCaseAnalyze = Path(mutationTestCaseAnalyze).AbsolutePath;
            if (mutationTesterRuntime != 0)
                mutationTest.mutationTesterRuntime = mutationTesterRuntime.dur!"msecs";
            if (!maxRuntime.empty)
                mutationTest.maxRuntime = parseDuration(maxRuntime);
        }

        void reportG(string[] args) {
            string[] compile_dbs;
            string logDir;

            data.toolMode = ToolMode.report;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compile_dbs,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &db,
                   "diff-from-stdin", "report alive mutants in the areas indicated as changed in the diff", &report.unifiedDiff,
                   "level", "the report level of the mutation data " ~ format("[%(%s|%)]", [EnumMembers!ReportLevel]), &report.reportLevel,
                   "logdir", "Directory to write log files to (default: .)", &logDir,
                   "mutant", "kind of mutation to report " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                   "out", out_help, &workArea.rawRoot,
                   "restrict", restrict_help, &workArea.rawRestrict,
                   "section", "sections to include in the report " ~ format("[%(%s|%)]", [EnumMembers!ReportSection]), &report.reportSection,
                   "section-tc_stat-num", "number of test cases to report", &report.tcKillSortNum,
                   "section-tc_stat-sort", "sort order when reporting test case kill stat " ~ format("[%(%s|%)]", [EnumMembers!ReportKillSortOrder]), &report.tcKillSortOrder,
                   "style", "kind of report to generate " ~ format("[%(%s|%)]", [EnumMembers!ReportKind]), &report.reportKind,
                   );
            // dfmt on

            if (report.reportSection.length != 0 && report.reportLevel != ReportLevel.summary) {
                logger.error("Combining --section and --level is not supported");
                help_info.helpWanted = true;
            }

            if (logDir.empty)
                logDir = ".";
            report.logDir = logDir.Path.AbsolutePath;

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
                "mutant", "mutants to operate on " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                "operation", "administrative operation to perform " ~ format("[%(%s|%)]", [EnumMembers!AdminOperation]), &admin.adminOp,
                "test-case-regex", "regex to use when removing test cases", &admin.testCaseRegex,
                "status", "change mutants with this state to the value specified by --to-status " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &admin.mutantStatus,
                "to-status", "reset mutants to state (default: unknown) " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &admin.mutantToStatus,
		"id", "specify mutant to mark", &mut_id_string,
		"rationale", "rationale for marking mutant", &admin.mutant_rationale,
		);
            // dfmt on

            if (dump_conf)
                data.toolMode = ToolMode.dumpConfig;
            else if (init_conf)
                data.toolMode = ToolMode.initConfig;
	    if (!mut_id_string.empty) {
		import std.conv: to;
		data.mutant_id = to!long(mut_id_string);
	    }
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

        if (db.length != 0)
            data.db = AbsolutePath(FileName(db));
        else if (data.db.length == 0)
            data.db = "dextool_mutate.sqlite3".Path.AbsolutePath;

        if (workArea.rawRoot.length != 0)
            workArea.outputDirectory = AbsolutePath(Path(workArea.rawRoot.asAbsNormPath));
        else if (workArea.outputDirectory.length == 0) {
            workArea.rawRoot = ".";
            workArea.outputDirectory = workArea.rawRoot.Path.AbsolutePath;
        }

        if (workArea.rawRestrict.length != 0)
            workArea.restrictDir = workArea.rawRestrict.map!(a => AbsolutePath(FileName(a))).array;
        else if (workArea.restrictDir.length == 0) {
            workArea.rawRestrict = [workArea.rawRoot];
            workArea.restrictDir = [workArea.outputDirectory];
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

/// Update the config from the users input.
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
    logger.infof("Reading compilation database:\n%-(%s\n%)", ap.compileDb.dbs);

    logger.info(
            "Analyze and mutation of files will only be done on those inside this directory root");
    logger.info("  User input: ", ap.workArea.rawRoot);
    logger.info("  Real path: ", ap.workArea.outputDirectory);
    logger.info(ap.workArea.rawRestrict.length != 0,
            "Restricting mutation to files in the following directory tree(s)");

    assert(ap.workArea.rawRestrict.length == ap.workArea.restrictDir.length);
    foreach (idx; 0 .. ap.workArea.rawRestrict.length) {
        if (ap.workArea.rawRestrict[idx] == ap.workArea.rawRoot)
            continue;
        logger.info("  User input: ", ap.workArea.rawRestrict[idx]);
        logger.info("  Real path: ", ap.workArea.restrictDir[idx]);
    }

    logger.info("Excluding files inside the following directory tree(s) from analysis");
    foreach (root; ap.analyze.exclude)
        logger.info("  Real path: ", root);
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
    import std.conv : to;
    import std.file : exists, readText;
    import std.path : dirName, buildPath;
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

    alias Fn = void delegate(ref ArgParser c, ref TOMLValue v);
    Fn[string] callbacks;

    callbacks["analyze.exclude"] = (ref ArgParser c, ref TOMLValue v) {
        c.analyze.exclude = v.array.map!(a => a.str.Path.AbsolutePath).array;
    };

    callbacks["workarea.root"] = (ref ArgParser c, ref TOMLValue v) {
        c.workArea.rawRoot = v.str;
    };
    callbacks["workarea.restrict"] = (ref ArgParser c, ref TOMLValue v) {
        c.workArea.rawRestrict = v.array.map!(a => a.str).array;
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
        c.mutationTest.mutationTester = ShellCommand(v.str);
    };
    callbacks["mutant_test.test_cmd_timeout"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTesterRuntime = v.integer.dur!"msecs";
    };
    callbacks["mutant_test.build_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationCompile = ShellCommand(v.str);
    };
    callbacks["mutant_test.analyze_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTestCaseAnalyze = Path(v.str).AbsolutePath;
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
        }
    };
    callbacks["mutant_test.detected_dropped_test_case"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.mutationTest.onRemovedTestCases = v.str.to!(ConfigMutationTest.RemovedTestCases);
        } catch (Exception e) {
            logger.info("Available alternatives: ",
                    [EnumMembers!(ConfigMutationTest.RemovedTestCases)]);
        }
    };
    callbacks["mutant_test.oldest_mutants"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.mutationTest.onOldMutants = v.str.to!(ConfigMutationTest.OldMutant);
        } catch (Exception e) {
            logger.info("Available alternatives: ", [
                    EnumMembers!(ConfigMutationTest.OldMutant)
                    ]);
        }
    };
    callbacks["mutant_test.oldest_mutants_nr"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.oldMutantsNr = v.integer;
    };
    callbacks["report.style"] = (ref ArgParser c, ref TOMLValue v) {
        c.report.reportKind = v.str.to!ReportKind;
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

    iterSection(rval, "analyze");
    iterSection(rval, "workarea");
    iterSection(rval, "database");
    iterSection(rval, "compiler");
    iterSection(rval, "compile_commands");
    iterSection(rval, "mutant_test");
    iterSection(rval, "report");

    parseTestGroups(rval, doc);
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
