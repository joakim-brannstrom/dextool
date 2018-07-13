/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

TODO:
- Move entire else-statement in foreach-loop into separate file
*/

module dextool.plugin.runner;

import std.stdio;
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
    import dextool.plugin.eqdetect.backend : DbHandler;
    import dextool.plugin.eqdetect.backend.type : Mutation;
    auto dbHandler = new DbHandler(to!string(pargs.file));
    Mutation[] mutations = dbHandler.getMutations();


    TUVisitor visitor;
    ExitStatusType exit_status;

    import dextool.utility : analyzeFile;
    import dextool.plugin.eqdetect.backend.type: ErrorResult;
    import dextool.plugin.eqdetect.backend.parser : errorTextParser;
    ErrorResult errorResult;

    foreach(m ; mutations){
        visitor = new TUVisitor(m);
        exit_status = analyzeFile(AbsolutePath(FileName(m.path)), cflags, visitor, ctx);

        if (exit_status != ExitStatusType.Ok){
            logger.info("Could not analyze file: " ~ m.path);
        } else {
            import std.path : baseName;
            import dextool.plugin.eqdetect.backend : writeToFile, SnippetFinder;
            FileName source_path = writeToFile(visitor.generatedSource.render, baseName(m.path), m.kind, m.id, "_source_");
            FileName mutant_path = writeToFile(visitor.generatedMutation.render, baseName(m.path), m.kind, m.id, "_mutant_");
            auto s = SnippetFinder.generateKlee(visitor.function_params, source_path,
                                                mutant_path, visitor.function_name);
            writeToFile(s, baseName(m.path), m.kind, m.id, "_klee_");

            import std.process: executeShell;
            import std.file: getcwd;
            import std.format : format;

            // Spawn a shell and create the klee-container with a mounted volume (current build directory)
            // The created container will execute the klee.sh script and after execution get removed
            logger.info("KLEE execution started");
            auto klee_exec_out = executeShell(format("docker run -it --name=klee_container4 -v %s:/home/klee/mounted klee/klee mounted/klee.sh", getcwd())).output;
            logger.info(klee_exec_out);

            // Remove the container and cleanup the temporary directory created
            executeShell("docker rm klee_container4");
            executeShell("rm -rf eqdetect_generated_files/*");

            // parse the result from KLEE
            errorResult = errorTextParser("result.txt");

            // remove the result-file
            import std.file: remove;
            remove("result.txt");


            import dextool.plugin.mutate.backend.type : mutationStruct = Mutation;
            auto dbHandler2 = new DbHandler(to!string(pargs.file));
            scope (exit) destroy(dbHandler2);
            {
                switch (errorResult.status){
                    case "Eq":
                        dbHandler2.setEquivalence(m.id, mutationStruct.eq.equivalent);
                        break;
                    case "Halt":
                        dbHandler2.setEquivalence(m.id, mutationStruct.eq.timeout);
                        break;
                    default:
                        dbHandler2.setEquivalence(m.id, mutationStruct.eq.not_equivalent);
                        break;
                }
            }
            writeln("---------------------------------------");
        }
    }

    import std.process;
    executeShell("rm -rf eqdetect_generated_files");

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
        import std.stdio : writeln;

        defaultGetoptPrinter("Usage: dextool eqdetect [options] [--in=] [-- CFLAGS...]",
                help_info.options);
    }
}
