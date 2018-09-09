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

import logger = std.experimental.logger;

public import dextool.plugin.mutate.type;
public import dextool.plugin.mutate.backend : Mutation;

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
}

/// Extract and cleanup user input from the command line.
struct ArgParser {
    import std.typecons : Nullable;
    import std.conv : ConvException;
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;
    import std.traits : EnumMembers;
    import dextool.type : FileName;
    import dextool.plugin.mutate.config;

    struct Data {
        string[] inFiles;
        string[] cflags;
        string[] compileDb;

        string outputDirectory = ".";
        string[] restrictDir;

        string db = "dextool_mutate.sqlite3";
        string mutationTester;
        string mutationCompile;
        string mutationTestCaseAnalyze;
        TestCaseAnalyzeBuiltin[] mutationTestCaseBuiltin;

        long mutationTesterRuntime;
        Nullable!long mutationId;

        bool help;
        bool shortPluginHelp;
        bool dryRun;

        MutationKind[] mutation;
        MutationOrder mutationOrder;

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

    /**
     * trusted: getopt is safe in dmd-2.077.0.
     * Remove the trusted attribute when upgrading the minimal required version
     * of the D frontend.
     */
    void parse(string[] args) @trusted {
        import std.traits : EnumMembers;
        import std.format : format;

        static import std.getopt;

        const db_help = "sqlite3 database to use (default: dextool_mutate.sqlite3)";
        const restrict_help = "restrict analysis to files in this directory tree (default: .)";
        const out_help = "path used as the root for mutation/reporting of files (default: .)";

        void analyzerG(string[] args) {
            data.toolMode = ToolMode.analyzer;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &data.compileDb,
                   "db", db_help, &data.db,
                   "in", "Input file to parse (default: all files in the compilation database)", &data.inFiles,
                   "out", out_help, &data.outputDirectory,
                   "restrict", restrict_help, &data.restrictDir,
                   );
            // dfmt on
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
            data.toolMode = ToolMode.test_mutants;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile", "program to use to compile the mutant", &data.mutationCompile,
                   "db", db_help, &data.db,
                   "dry-run", "do not write data to the filesystem", &data.dryRun,
                   "mutant", "kind of mutation to test " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                   "order", "determine in what order mutations are chosen " ~ format("[%(%s|%)]", [EnumMembers!MutationOrder]), &data.mutationOrder,
                   "out", out_help, &data.outputDirectory,
                   "restrict", restrict_help, &data.restrictDir,
                   "test", "program used to run the test suite", &data.mutationTester,
                   "test-case-analyze-builtin", "builtin analyzer of output from testing frameworks to find failing test cases", &data.mutationTestCaseBuiltin,
                   "test-case-analyze-cmd", "program used to find what test cases killed the mutant", &data.mutationTestCaseAnalyze,
                   "test-timeout", "timeout to use for the test suite (msecs)", &data.mutationTesterRuntime,
                   );
            // dfmt on
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
                   );
            // dfmt on

            if (data.report.reportSection.length != 0
                    && data.report.reportLevel != ReportLevel.summary) {
                logger.error("Combining --section and --level is not supported");
                help_info.helpWanted = true;
            }
        }

        void adminG(string[] args) {
            data.toolMode = ToolMode.admin;
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                "db", db_help, &data.db,
                "mutant", "mutants to operate on " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &data.mutation,
                "operation", "administrative operation to perform " ~ format("[%(%s|%)]", [EnumMembers!AdminOperation]), &data.adminOp,
                "test-case-regex", "regex to use when removing test cases", &data.testCaseRegex,
                "status", "change the state of the mutants --to-status unknown which currently have status " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &data.mutantStatus,
                "to-status", "reset mutants to state (default: unknown) " ~ format("[%(%s|%)]", [EnumMembers!(Mutation.Status)]), &data.mutantToStatus,
                );
            // dfmt on
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

        cflags = args.find("--").drop(1).array();
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
            logger.errorf("--mutant possible values: %(%s|%)", [EnumMembers!MutationKind]);
            logger.errorf("--order possible values: %(%s|%)", [EnumMembers!MutationOrder]);
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
