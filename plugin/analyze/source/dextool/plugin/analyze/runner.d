/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.runner;

import logger = std.experimental.logger;

import dextool.type : ExitStatusType, FileName, AbsolutePath;

ExitStatusType runPlugin(string[] args) {
    import std.stdio : writeln, writefln;
    import dextool.compilation_db : CompileCommandDB, fromArgCompileDb;
    import dextool.plugin.analyze.raw_config;
    import dextool.plugin.analyze.analyze : AnalyzeBuilder, AnalyzeResults,
        doAnalyze;

    RawConfiguration pargs;
    pargs.parse(args);

    // the dextool plugin architecture requires that two lines are printed upon
    // request by the main function.
    //  - a name of the plugin.
    //  - a oneliner description.
    if (pargs.shortPluginHelp) {
        writeln("analyze");
        writeln("static code analysis of c/c++ source code");
        return ExitStatusType.Ok;
    } else if (pargs.errorHelp) {
        pargs.printHelp;
        return ExitStatusType.Errors;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    }

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    // dfmt off
    auto analyze_builder = AnalyzeBuilder.make
        .mcCabe(pargs.mccabe);
    auto analyze_results = AnalyzeResults.make
        .mcCabe(pargs.mccabe, pargs.mccabeThreshold)
        .json(pargs.outputJson)
        .stdout(pargs.outputStdout)
        .outputDirectory(pargs.outdir)
        .finalize;
    // dfmt on

    doAnalyze(analyze_builder, analyze_results, pargs.cflags, pargs.files,
            compile_db, AbsolutePath(FileName(pargs.restrictDir)), pargs.workerThreads);

    analyze_results.dumpResult;

    return ExitStatusType.Ok;
}
