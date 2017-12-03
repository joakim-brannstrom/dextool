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
 * #SPC-plugin_mutate_memory_safety
 */
auto runPlugin(string[] args) @safe {
    import std.stdio : writeln;
    import logger = std.experimental.logger;
    import dextool.type;
    import dextool.utility;
    import dextool.xml : makeXmlLog;
    import dextool.plugin.mutate.frontend : buildFrontend, ArgParser;

    ArgParser argp;
    argp.parse(args);

    debug logger.trace(args);
    debug logger.trace(argp);

    if (argp.shortPluginHelp) {
        writeln("mutate");
        writeln("mutation testing plugin");
        return ExitStatusType.Ok;
    } else if (argp.help) {
        argp.printHelp;
        return ExitStatusType.Ok;
    }

    auto frontend = buildFrontend(argp);
    return frontend.run;
}
