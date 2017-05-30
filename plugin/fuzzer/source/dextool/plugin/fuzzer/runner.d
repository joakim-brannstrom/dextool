/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.runner;

auto runPlugin(string[] args) {
    import std.array : appender;
    import std.regex : regex;
    import std.stdio : writeln;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import dextool.plugin.fuzzer.frontend.frontend;
    import dextool.plugin.fuzzer.frontend.raw_args;

    RawConfiguration pargs;
    pargs.parse(args);

    if (pargs.shortPluginHelp) {
        writeln("fuzzer");
        writeln("generate a wrapper for a block of code to fuzz with AFL");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.inFiles.length == 0) {
        writeln("Missing required argument --in");
        return ExitStatusType.Errors;
    }

    auto frontend = FuzzerFrontend.make(pargs);

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    return genFuzzer(frontend, pargs.cflags, compile_db,
            InFiles(pargs.inFiles), regex(pargs.stripInclude));
}
