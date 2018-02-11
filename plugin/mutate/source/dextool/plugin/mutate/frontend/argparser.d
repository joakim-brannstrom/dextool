/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.frontend.argparser;

import logger = std.experimental.logger;

public import dextool.plugin.mutate.type;

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
}

/// Extract and cleanup user input from the command line.
struct ArgParser {
    import std.typecons : Nullable;
    import std.conv : ConvException;
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;
    import std.traits : EnumMembers;
    import dextool.type : FileName;

    string[] inFiles;
    string[] cflags;
    string[] compileDb;

    string outputDirectory;
    string restrictDir = ".";

    string db = "dextool_mutate.sqlite3";
    string mutationTester;
    string mutationCompile;

    long mutationTesterRuntime;
    Nullable!long mutationId;

    bool help;
    bool shortPluginHelp;
    bool dryRun;

    MutationKind[] mutation;
    MutationOrder mutationOrder;
    ReportKind reportKind;
    ReportLevel reportLevel;

    ToolMode toolMode;

    private GetoptResult help_info;

    alias GroupF = void delegate(string[]) @system;
    GroupF[string] groups;

    /**
     * trusted: getopt is safe in dmd-2.077.0.
     * Remove the trusted attribute when upgrading the minimal required version
     * of the D frontend.
     */
    void parse(string[] args) @trusted {
        import std.traits : EnumMembers;
        import std.format : format;

        static import std.getopt;

        void analyzerG(string[] args) {
            toolMode = ToolMode.analyzer;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "db", "sqlite3 database to use", &db,
                   "in", "Input file to parse (at least one)", &inFiles,
                   "out", "directory for generated files (default: same as --restrict)", &outputDirectory,
                   "restrict", "restrict analysis to files in this directory tree (default: .)", &restrictDir,
                   );
            // dfmt on
        }

        void generateMutantG(string[] args) {
            toolMode = ToolMode.generate_mutant;
            string cli_mutation_id;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "db", "sqlite3 database to use", &db,
                   "out", "directory for generated files (default: same as --restrict)", &outputDirectory,
                   "restrict", "restrict mutation to files in this directory tree (default: .)", &restrictDir,
                   "mutant-id", "generate a specific mutation", &cli_mutation_id,
                   );
            // dfmt on

            try {
                import std.conv : to;

                if (cli_mutation_id.length != 0)
                    mutationId = cli_mutation_id.to!long;
            }
            catch (ConvException e) {
                logger.infof("Invalid mutation point '%s'. It must be in the range [0, %s]",
                        cli_mutation_id, long.max);
            }
        }

        void testMutantsG(string[] args) {
            toolMode = ToolMode.test_mutants;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "db", "sqlite3 database to use", &db,
                   "dry-run", "do not write data to the filesystem", &dryRun,
                   "out", "directory for generated files (default: same as --restrict)", &outputDirectory,
                   "restrict", "restrict mutation to files in this directory tree (default: .)", &restrictDir,
                   "mutant", "kind of mutation to perform " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutation,
                   "compile", "program to use to compile the mutant", &mutationCompile,
                   "order", "determine in what order mutations are chosen " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutationOrder,
                   "test", "program to use to execute the mutant tester", &mutationTester,
                   "test-timeout", "timeout to use for the test suite (msecs)", &mutationTesterRuntime,
                   );
            // dfmt on
        }

        void reportG(string[] args) {
            toolMode = ToolMode.report;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "db", "sqlite3 database to use", &db,
                   "out", "directory for generated files (default: same as --restrict)", &outputDirectory,
                   "restrict", "restrict mutation to files in this directory tree (default: .)", &restrictDir,
                   "mutant", "kind of mutation to perform " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutation,
                   "style", "kind of report to generate " ~ format("[%(%s|%)]", [EnumMembers!ReportKind]), &reportKind,
                   "level", "the report level of the mutation data " ~ format("[%(%s|%)]", [EnumMembers!ReportLevel]), &reportLevel,
                   );
            // dfmt on
        }

        groups["analyze"] = &analyzerG;
        groups["generate"] = &generateMutantG;
        groups["test"] = &testMutantsG;
        groups["report"] = &reportG;

        if (args.length == 2 && args[1] == "--short-plugin-help") {
            shortPluginHelp = true;
            return;
        }

        if (args.length < 2) {
            logger.error("Missing command group");
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
            }
            catch (std.getopt.GetOptException ex) {
                logger.error(ex.msg);
                help = true;
            }
            catch (Exception ex) {
                logger.error(ex.msg);
                help = true;
            }
        } else {
            logger.error("Unknown command group: ", cg);
            help = true;
            return;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        cflags = args.find("--").drop(1).array();
    }

    /**
     * Trusted:
     * The only input is a static string and data derived from getopt itselt.
     * Assuming that getopt in phobos behave well.
     */
    void printHelp() @trusted {
        string base_help = "Usage: dextool mutate COMMAND_GROUP [options] [-- CFLAGS...]";

        switch (toolMode) with (ToolMode) {
        case none:
            logger.errorf("The command groups are: %(%s %)", groups.byKey);
            break;
        case analyzer:
            base_help = "Usage: dextool mutate analyze [options] [-- CFLAGS...]";
            break;
        case generate_mutant:
            base_help = "Usage: dextool mutate generate [options] [-- CFLAGS...]";
            break;
        case test_mutants:
            base_help = "Usage: dextool mutate test [options] [-- CFLAGS...]";
            logger.errorf("--mutant possible values: %(%s %)", [EnumMembers!MutationKind]);
            break;
        case report:
            base_help = "Usage: dextool mutate report [options] [-- CFLAGS...]";
            logger.errorf("--mutant possible values: %(%s %)", [EnumMembers!MutationKind]);
            logger.errorf("--report possible values: %(%s %)", [EnumMembers!ReportKind]);
            logger.errorf("--report-level possible values: %(%s %)", [EnumMembers!ReportLevel]);
            break;
        default:
            break;
        }

        defaultGetoptPrinter(base_help, help_info.options);
    }
}
