/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file is the main entrypoint to the plugin.

TODO:
- Break out the remaining for-loop to mutation_handler (run-function or similar)
- Break out RawConfiguration into frontend
*/

module dextool.plugin.runner;

import std.stdio : writeln;
import logger = std.experimental.logger;

import dextool.type : ExitStatusType, FileName, AbsolutePath;

ExitStatusType runPlugin(string[] args) {
    RawConfiguration pargs;
    pargs.parse(args);

    if (pargs.shortPluginHelp) {
        writeln("eqdetect");
        writeln("Find for-loops in given file");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.file.length == 0) {
        writeln("Missing file --in");
        return ExitStatusType.Errors;
    }

    import dextool.utility : prependDefaultFlags, PreferLang;

    const auto cflags = prependDefaultFlags(pargs.cflags, PreferLang.cpp);

    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.plugin.eqdetect.backend : TUVisitor;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    import std.conv : to;
    import dextool.plugin.eqdetect.backend.dbhandler : initDB, getMutations;
    import dextool.plugin.eqdetect.backend.type : Mutation;

    initDB(to!string(pargs.file));
    Mutation[] mutations = getMutations();

    TUVisitor visitor;
    ExitStatusType exit_status;

    import dextool.utility : analyzeFile;

    foreach (m; mutations) {
        visitor = new TUVisitor(m);
        import std.path : stripExtension;
        exit_status = analyzeFile(AbsolutePath(FileName(stripExtension(m.path)~".hpp",)), cflags, visitor, ctx);
        exit_status = analyzeFile(AbsolutePath(FileName(m.path)), cflags, visitor, ctx);

        if (exit_status != ExitStatusType.Ok) {
            logger.info("Could not analyze file: " ~ m.path);

        } else {
            import dextool.plugin.eqdetect.backend : handleMutation;
            handleMutation(visitor, m);

            // separate the output
            writeln("---------------------------------------");
        }
    }

    return exit_status;
}

/** Handle parsing of user arguments.
*/
struct RawConfiguration {
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;

    bool shortPluginHelp;
    bool help;
    string file;
    string[] cflags;

    private GetoptResult help_info;

    void parse(string[] args) {
        static import std.getopt;

        try {
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "in", "Input file to parse", &file);
            // dfmt on
            help = help_info.helpWanted;
        } catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    void printHelp() {
        defaultGetoptPrinter("Usage: dextool eqdetect [options] [--in=] [-- CFLAGS...]",
                help_info.options);
    }
}
