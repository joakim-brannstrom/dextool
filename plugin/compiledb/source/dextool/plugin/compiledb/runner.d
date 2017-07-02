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

auto runPlugin(string[] args) {
    import std.stdio : writeln;
    import dextool.type : ExitStatusType;
    import dextool.plugin.compiledb.frontend;
    import dextool.plugin.compiledb.raw_args;

    RawConfiguration pargs;
    pargs.parse(args);

    if (pargs.shortPluginHelp) {
        writeln("compiledb");
        writeln("manipulate Compilation Command Databases");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.inCoompileDb.length == 0) {
        writeln("Missing required argument: DBFILE");
        return ExitStatusType.Errors;
    }

    logger.trace(pargs);

    return doCompileDb(pargs);
}
