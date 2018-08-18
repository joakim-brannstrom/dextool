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

import colorlog : VerboseMode, confLogger;

import dextool.type : FileName, ExitStatusType;

/** Parse the raw command line.
 */
VerboseMode parseLogLevel(string[] args) {
    import std.algorithm : findAmong;
    import std.array : empty;

    return findAmong(args, ["-d", "--debug"]).empty ? VerboseMode.info : VerboseMode.trace;
}

int main(string[] args) {
    import std.algorithm : filter, among;
    import std.array : array;
    import std.stdio : writeln;

    confLogger(parseLogLevel(args));

    // holds the remining arguments after -d/--debug has bee removed
    auto remining_args = args.filter!(a => !a.among("-d", "--debug")).array();

    // REQUIRED BY PLUGINS USING THIS MAIN
    import dextool.plugin.runner : runPlugin;

    return runPlugin(remining_args);
}
