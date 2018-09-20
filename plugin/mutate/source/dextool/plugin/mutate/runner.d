/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.runner;

/**
 * Tagging the main entry point to the plugin with @safe to fulfill
 * #SPC-memory_safety
 */
auto runPlugin(string[] args) @safe {
    import std.stdio : writeln;
    import std.traits : ReturnType;
    import logger = std.experimental.logger;
    import dextool.type;
    import dextool.utility;
    import dextool.xml : makeXmlLog;
    import dextool.plugin.mutate.frontend : ArgParser, cliToMiniConfig,
        loadConfig, runMutate;

    auto argp = ArgParser.make;
    argp.miniConf = cliToMiniConfig(args);

    if (argp.miniConf.shortPluginHelp) {
        writeln("mutate");
        writeln("mutation testing plugin");
        return ExitStatusType.Ok;
    }

    logger.trace(args);

    loadConfig(argp);
    argp.parse(args);

    logger.trace(argp);

    if (argp.help || argp.data.exitStatus != ExitStatusType.Ok) {
        argp.printHelp;
        return argp.data.exitStatus;
    }

    return runMutate(argp);
}
