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

import core.time : Duration, dur;
import std.exception : collectException;
import std.typecons : Nullable;
import logger = std.experimental.logger;

public import dextool.plugin.mutate.type;
public import dextool.plugin.mutate.backend : Mutation;
import dextool.type : AbsolutePath, Path;

@safe:

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
}

/// Settings for mutation testing
struct ConfigMutationTest {
    AbsolutePath mutationTester;
    AbsolutePath mutationCompile;
    AbsolutePath mutationTestCaseAnalyze;
    TestCaseAnalyzeBuiltin[] mutationTestCaseBuiltin;
    Nullable!Duration mutationTesterRuntime;
}

/// Settings for the administration mode
struct ConfigAdmin {
}

/// Extract and cleanup user input from the command line.
struct ArgParser {
    import std.typecons : Nullable;
    import std.conv : ConvException;
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;
    import std.traits : EnumMembers;
    import dextool.type : FileName;
    import dextool.plugin.mutate.config;

    /// Minimal data needed to bootstrap the configuration.
    MiniConfig miniConf;

    ConfigCompileDb compileDb;
    ConfigCompiler compiler;
    ConfigMutationTest mutationTest;

    struct Data {
        string[] inFiles;

        string outputDirectory = ".";
        string[] restrictDir;

        string db = "dextool_mutate.sqlite3";

        bool help;
        bool shortPluginHelp;
        bool dryRun;

        MutationKind[] mutation;
        MutationOrder mutationOrder;

        Nullable!long mutationId;

        ReportConfig report;

        AdminOperation adminOp;
        Mutation.Status mutantStatus;
        Mutation.Status mutantToStatus;
        string testCaseRegex;

        ToolMode toolMode;
    }

    Data data;
    alias data this;

    private GetoptResult help_info;

    alias GroupF = void delegate(string[]) @system;
    GroupF[string] groups;

    /// Returns: a config object with default values.
    static ArgParser make() @safe {
        import dextool.compilation_db : defaultCompilerFlagFilter,
            CompileCommandFilter;

        ArgParser r;
        r.compileDb.flagFilter = CompileCommandFilter(defaultCompilerFlagFilter, 1);
        return r;
    }

    /// Convert the configuration to a TOML file.
    string toTOML() @trusted {
        import std.algorithm : joiner;
        import std.ascii : newline;
        import std.array : appender, array;
        import std.format : format;
        import std.utf : toUTF8;
        import std.traits : EnumMembers;

        auto app = appender!(string[])();

        app.put("[compiler]");
        app.put("# extra flags to pass on to the compiler");
        app.put(`# extra_flags = [ "-std=c++11" ]`);
        app.put(null);

        app.put("[compile_commands]");
        app.put("# search for compile_commands.json in this paths");
        if (compileDb.dbs.length == 0)
            app.put(format("search_paths = %s", ["./compile_commands.json"]));
        else
            app.put(format("search_paths = %s", compileDb.rawDbs));
        app.put("# flags to remove when analyzing a file in the DB");
        app.put(format("# filter = [%(%s, %)]", compileDb.flagFilter.filter));
        app.put("# compiler arguments to skip from the beginning. Needed when the first argument is NOT a compiler but rather a wrapper");
        app.put(format("# skip_compiler_args = %s", compileDb.flagFilter.skipCompilerArgs));
        app.put(null);

        app.put("[mutant_test]");
        app.put("# program used to run the test suite");
        app.put("# test_cmd =");
        app.put("# timeout to use for the test suite (msecs)");
        app.put("# test_cmd_timeout =");
        app.put("# program used to compile the application");
        app.put("# compile_cmd =");
        app.put(
                "# program used to analyze the output from the test suite for test cases that killed the mutant");
        app.put("# analyze_cmd = ");
        app.put("# builtin analyzer of output from testing frameworks to find failing test cases");
        app.put(format("# analyze_using_builtin = [%(%s, %)]",
                [EnumMembers!TestCaseAnalyzeBuiltin]));

        return app.data.joiner(newline).toUTF8;
    }

    /**
     * trusted: getopt is safe in dmd-2.077.0.
     * Remove the trusted attribute when upgrading the minimal required version
     * of the D frontend.
     */
    void parse(string[] args) @trusted {
        import std.algorithm : filter, map;
        import std.array : array;
        import std.format : format;

        static import std.getopt;

        const db_help = "sqlite3 database to use (default: dextool_mutate.sqlite3)";
        const restrict_help = "restrict analysis to files in this directory tree (default: .)";
        const out_help = "path used as the root for mutation/reporting of files (default: .)";
        const conf_help = "load configuration (default: dextool_mutate.toml)";

        // not used but need to be here. The one used is in MiniConfig.
        string conf_file;

        void analyzerG(string[] args) {
            string[] compile_dbs;
            data.toolMode = ToolMode.analyzer;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compile_dbs,
                   "db", db_help, &data.db,
                   "in", "Input file to parse (default: all files in the compilation database)", &data.inFiles,
                   "out", out_help, &data.outputDirectory,
                   "restrict", restrict_help, &data.restrictDir,
                   );
            // dfmt on

            compileDb.rawDbs = compile_dbs;
            compileDb.dbs = compileDb.rawDbs
                .filter!(a => a.length != 0)
                .map!(a => Path(a).AbsolutePath)
                .array;
        }

        void generateMutantG(string[] args) {
            data.toolMode = ToolMode.generate_mutant;
            string cli_mutation_id;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "db", db_help, &data.db,
                   "out", out_help, &data.outputDirectory,
                   "restrict", restrict_help, &data.restrictDir,
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

            data.toolMode = ToolMode.test_mutants;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile", "program used to compile the application", &mutationCompile,
                   "c|config", conf_help, &conf_file,
                   "db", db_help, &data.db,
                   "dry-run", "do not write data to the filesystem", &data.dryRun,
                   "mutant", "kind of mutation to test " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                   "order", "determine in what order mutations are chosen " ~ format("[%(%s|%)]", [EnumMembers!MutationOrder]), &data.mutationOrder,
                   "out", out_help, &data.outputDirectory,
                   "restrict", restrict_help, &data.restrictDir,
                   "test", "program used to run the test suite", &mutationTester,
                   "test-case-analyze-builtin", "builtin analyzer of output from testing frameworks to find failing test cases", &mutationTest.mutationTestCaseBuiltin,
                   "test-case-analyze-cmd", "program used to find what test cases killed the mutant", &mutationTestCaseAnalyze,
                   "test-timeout", "timeout to use for the test suite (msecs)", &mutationTesterRuntime,
                   );
            // dfmt on

            mutationTest.mutationTester = Path(mutationTester).AbsolutePath;
            mutationTest.mutationCompile = Path(mutationCompile).AbsolutePath;
            if (mutationTestCaseAnalyze.length != 0)
                mutationTest.mutationTestCaseAnalyze = Path(mutationTestCaseAnalyze).AbsolutePath;
            if (mutationTesterRuntime != 0)
                mutationTest.mutationTesterRuntime = mutationTesterRuntime.dur!"msecs";
        }

        void reportG(string[] args) {
            data.toolMode = ToolMode.report;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "db", db_help, &data.db,
                   "level", "the report level of the mutation data " ~ format("[%(%s|%)]", [EnumMembers!ReportLevel]), &data.report.reportLevel,
                   "out", out_help, &data.outputDirectory,
                   "restrict", restrict_help, &data.restrictDir,
                   "mutant", "kind of mutation to report " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                   "section", "sections to include in the report " ~ format("[%(%s|%)]", [EnumMembers!ReportSection]), &data.report.reportSection,
                   "style", "kind of report to generate " ~ format("[%(%s|%)]", [EnumMembers!ReportKind]), &data.report.reportKind,
                   "section-tc_stat-num", "number of test cases to report", &data.report.tcKillSortNum,
                   "section-tc_stat-sort", "sort order when reporting test case kill stat " ~ format("[%(%s|%)]", [EnumMembers!ReportKillSortOrder]), &data.report.tcKillSortOrder,
                   );
            // dfmt on

            if (data.report.reportSection.length != 0
                    && data.report.reportLevel != ReportLevel.summary) {
                logger.error("Combining --section and --level is not supported");
                help_info.helpWanted = true;
            }
        }

        void adminG(string[] args) {
            bool dump_conf;
            data.toolMode = ToolMode.admin;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                "db", db_help, &data.db,
                "dump-config", "dump the detailed configuration used", &dump_conf,
                "mutant", "mutants to operate on " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                "operation", "administrative operation to perform " ~ format("[%(%s|%)]", [EnumMembers!AdminOperation]), &data.adminOp,
                "test-case-regex", "regex to use when removing test cases", &data.testCaseRegex,
                "status", "change the state of the mutants --to-status unknown which currently have status " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &data.mutantStatus,
                "to-status", "reset mutants to state (default: unknown) " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &data.mutantToStatus,
                );
            // dfmt on

            if (dump_conf)
                data.toolMode = ToolMode.dumpConfig;
        }

        groups["analyze"] = &analyzerG;
        groups["generate"] = &generateMutantG;
        groups["test"] = &testMutantsG;
        groups["report"] = &reportG;
        groups["admin"] = &adminG;

        if (args.length == 2 && args[1] == "--short-plugin-help") {
            shortPluginHelp = true;
            return;
        }

        if (args.length < 2) {
            logger.error("Missing command");
            help = true;
            return;
        }

        const string cg = args[1];
        string[] subargs = args[0 .. 1];
        if (args.length > 2)
            subargs ~= args[2 .. $];

        if (auto f = cg in groups) {
            try {
                (*f)(subargs);
                help = help_info.helpWanted;
            } catch (std.getopt.GetOptException ex) {
                logger.error(ex.msg);
                help = true;
            } catch (Exception ex) {
                logger.error(ex.msg);
                help = true;
            }
        } else {
            logger.error("Unknown command: ", cg);
            help = true;
            return;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        compiler.extraFlags = args.find("--").drop(1).array();
    }

    /**
     * Trusted:
     * The only input is a static string and data derived from getopt itselt.
     * Assuming that getopt in phobos behave well.
     */
    void printHelp() @trusted {
        import std.array : array;
        import std.algorithm : joiner, sort, map;
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
            logger.errorf("--test-case-analyze-builtin possible values: %(%s|%)",
                    [EnumMembers!TestCaseAnalyzeBuiltin]);
            break;
        case report:
            logger.errorf("--mutant possible values: %(%s|%)", [EnumMembers!MutationKind]);
            logger.errorf("--report possible values: %(%s|%)", [EnumMembers!ReportKind]);
            logger.errorf("--level possible values: %(%s|%)", [EnumMembers!ReportLevel]);
            logger.errorf("--section possible values: %(%s|%)", [EnumMembers!ReportSection]);
            break;
        case admin:
            logger.errorf("--mutant possible values: %(%s|%)", [EnumMembers!MutationKind]);
            logger.errorf("--operation possible values: %(%s|%)", [EnumMembers!AdminOperation]);
            logger.errorf("--status possible values: %(%s|%)", [EnumMembers!(Mutation.Status)]);
            break;
        default:
            break;
        }

        defaultGetoptPrinter(base_help, help_info.options);
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
    import std.algorithm : filter, map;
    import std.array : array;
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
        return;
    }

    alias Fn = void delegate(ref ArgParser c, ref TOMLValue v);
    Fn[string] callbacks;

    callbacks["compile_commands.search_paths"] = (ref ArgParser c, ref TOMLValue v) {
        c.compileDb.rawDbs = v.array.map!"a.str".array;
    };
    //callbacks["compile_commands.exclude"] = (ref ArgParser c, ref TOMLValue v) {
    //    c.staticCode.fileExcludeFilter = v.array.map!"a.str".array;
    //};
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

    callbacks["mutant_test.test_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTester = Path(v.str).AbsolutePath;
    };
    callbacks["mutant_test.test_cmd_timeout"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTesterRuntime = v.integer.dur!"msecs";
    };
    callbacks["mutant_test.compile_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationCompile = Path(v.str).AbsolutePath;
    };
    callbacks["mutant_test.analyze_cmd"] = (ref ArgParser c, ref TOMLValue v) {
        c.mutationTest.mutationTestCaseAnalyze = Path(v.str).AbsolutePath;
    };
    callbacks["mutation_test.analyze_using_builtin"] = (ref ArgParser c, ref TOMLValue v) {
        try {
            c.mutationTest.mutationTestCaseBuiltin = v.array.map!(
                    a => a.str.to!TestCaseAnalyzeBuiltin).array;
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    };

    void iterSection(ref ArgParser c, string sectionName) {
        if (auto section = sectionName in doc) {
            // specific configuration from section members
            foreach (k, v; *section) {
                if (auto cb = sectionName ~ "." ~ k in callbacks)
                    (*cb)(c, v);
                else
                    logger.infof("Unknown key '%s' in configuration section '%s'", k, sectionName);
            }
        }
    }

    iterSection(rval, "compile_commands");
    iterSection(rval, "compiler");
    iterSection(rval, "mutant_test");
}

/// Minimal config to setup path to config file.
struct MiniConfig {
    /// Value from the user via CLI, unmodified.
    string rawConfFile = "dextool_mutate.toml";

    /// The configuration file that has been loaded
    AbsolutePath confFile;
}

/// Returns: minimal config to load settings and setup working directory.
MiniConfig cliToMiniConfig(string[] args) @trusted nothrow {
    static import std.getopt;

    MiniConfig conf;

    try {
        std.getopt.getopt(args, std.getopt.config.keepEndOfOptions, std.getopt.config.passThrough,
                "c|config", "none not visible to the user", &conf.rawConfFile);
        conf.confFile = Path(conf.rawConfFile).AbsolutePath;
    } catch (Exception e) {
        logger.error("Invalid cli values: ", e.msg).collectException;
        logger.trace(conf).collectException;
    }

    return conf;
}
