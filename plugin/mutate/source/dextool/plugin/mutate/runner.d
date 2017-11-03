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
    import std.stdio : writeln;
    import logger = std.experimental.logger;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import dextool.xml : makeXmlLog;
    import dextool.plugin.mutate.frontend : ArgParser, runMutate;

    ArgParser argp;
    argp.parse(args);

    debug logger.trace(args);

    if (argp.shortPluginHelp) {
        writeln("mutate");
        writeln("mutation testing plugin");
        return ExitStatusType.Ok;
    } else if (argp.help) {
        argp.printHelp;
        return ExitStatusType.Ok;
    } else if (argp.inFiles.length == 0) {
        writeln("Missing required argument --in (at least one)");
        return ExitStatusType.Errors;
    }

    CompileCommandDB compile_db;
    if (argp.compileDb.length != 0) {
        compile_db = argp.compileDb.fromArgCompileDb;
    }

    return runMutate(argp, compile_db);
}
