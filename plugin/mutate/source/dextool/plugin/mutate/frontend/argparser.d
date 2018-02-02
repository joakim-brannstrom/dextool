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

    /**
     * trusted: getopt is safe in dmd-2.077.0.
     * Remove the trusted attribute when upgrading the minimal required version
     * of the D frontend.
     */
    void parse(string[] args) @trusted {
        import std.traits : EnumMembers;
        import std.format : format;

        static import std.getopt;

        try {
            string cli_mutation_id;

            // dfmt off
            // sort alphabetic
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "db", "sqlite3 database to use", &db,
                   "dry-run", "do not write data to the filesystem", &dryRun,
                   "in", "Input file to parse (at least one)", &inFiles,
                   "out", "directory for generated files (default: same as --restrict)", &outputDirectory,
                   "restrict", "restrict mutation to files in this directory tree (default: .)", &restrictDir,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "mode", "tool mode " ~ format("[%(%s|%)]", [EnumMembers!ToolMode]), &toolMode,
                   "mutant", "kind of mutation to perform " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutation,
                   "mutant-compile", "program to use to compile the mutant", &mutationCompile,
                   "mutant-id", "generate a specific mutation (only useful with mode generate_mutant)", &cli_mutation_id,
                   "mutant-order", "determine in what order mutations are chosen " ~ format("[%(%s|%)]", [EnumMembers!MutationKind]), &mutationOrder,
                   "mutant-test", "program to use to execute the mutant tester", &mutationTester,
                   "mutant-test-runtime", "runtime of the test suite used to test a mutation (msecs)", &mutationTesterRuntime,
                   "report", "kind of report to generate " ~ format("[%(%s|%)]", [EnumMembers!ReportKind]), &reportKind,
                   "report-level", "the report level of the mutation data " ~ format("[%(%s|%)]", [EnumMembers!ReportLevel]), &reportLevel,
                   );
            // dfmt on

            try {
                import std.conv : to;

                if (cli_mutation_id.length != 0)
                    mutationId = cli_mutation_id.to!long;
            }
            catch (ConvException e) {
                logger.infof("invalid mutation point '%s'. It must be in the range [0, %s]",
                        cli_mutation_id, long.max);
            }

            help = help_info.helpWanted;
        }
        catch (ConvException e) {
            import std.meta : AliasSeq;

            logger.error(e.msg);

            foreach (k; AliasSeq!(MutationKind, ToolMode, ReportKind, ReportLevel)) {
                logger.errorf("%s possible values: %(%s|%)", k.stringof, [EnumMembers!k]);
            }
            help = true;
        }
        catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }
        catch (Exception ex) {
            logger.error(ex.msg);
            help = true;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    /**
     * Trusted:
     * The only input is a static string and data derived from getopt itselt.
     * Assuming that getopt in phobos behave well.
     */
    void printHelp() @trusted {
        defaultGetoptPrinter("Usage: dextool mutate [options] [--in=] [-- CFLAGS...]",
                help_info.options);
    }
}
