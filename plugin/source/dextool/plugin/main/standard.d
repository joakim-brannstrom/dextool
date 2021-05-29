/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains an optional main function suitable for plugins.

It takes care of configuring the logging level in std.experimental.logger if
the user call the program with "-d|--debug".

This optional main function requires that:
 - the module is named dextool.plugin.runner
 - the module provides a function runPlugin that takes the program arguments.
*/
module dextool.plugin.main.standard;

import logger = std.experimental.logger;
import std.algorithm : filter, among, findAmong, canFind, sort;
import std.array : array, empty, appender;
import std.conv : to;
import std.stdio : writeln;

import colorlog : VerboseMode, confLogger, setLogLevel, toLogLevel, RootLogger,
    SpanMode, getRegisteredLoggers, parseLogNames, NameLevel;

/** Parse the raw command line.
 */
VerboseMode parseLogLevel(string[] args) {
    import std.traits : EnumMembers;

    if (!findAmong(args, ["-d", "--debug"]).empty)
        return VerboseMode.trace;

    auto verbose = findAmong(args, ["--verbose"]);
    try {
        if (verbose.length >= 2)
            return verbose[1].to!VerboseMode;
    } catch (Exception e) {
        logger.warning(e.msg);
        logger.info("--verbose supports ", [EnumMembers!VerboseMode]);
    }

    return VerboseMode.info;
}

NameLevel[] parseLogModules(string[] args, logger.LogLevel defaultLogLvl) {
    auto modules = findAmong(args, ["--verbose-module"]);
    try {
        if (modules.length >= 2)
            return parseLogNames(modules[1], defaultLogLvl);
    } catch (Exception e) {
        logger.info(e.msg);
    }

    return [NameLevel(RootLogger, defaultLogLvl)];
}

int main(string[] args) {
    if (canFind(args, "--short-plugin-help")) {
        confLogger(VerboseMode.warning);
        setLogLevel(RootLogger, logger.LogLevel.warning, SpanMode.depth);
    } else {
        const mode = parseLogLevel(args);
        confLogger(mode);

        const modules = parseLogModules(args, toLogLevel(mode));
        try {
            if (modules.empty)
                setLogLevel([RootLogger], toLogLevel(mode), SpanMode.depth);
            else
                setLogLevel(modules, SpanMode.depth);
        } catch (Exception e) {
            logger.info(e.msg);
            logger.info("--verbose-module supports ", getRegisteredLoggers.sort);
            logger.info("Use comma to separate name=logLevel");
        }
    }

    auto remArgs = appender!(string[])();
    for (size_t i = 0; i < args.length; ++i) {
        if (args[i].among("-d", "--debug")) {
            // skip one
        } else if (args[i].among("--verbose", "--verbose-module")) {
            ++i; //skip two
        } else {
            remArgs.put(args[i]);
        }
    }

    // REQUIRED BY PLUGINS USING THIS MAIN
    import dextool.plugin.runner : runPlugin;

    return runPlugin(remArgs.data);
}
