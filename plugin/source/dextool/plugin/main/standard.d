/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Main function suitable for plugins.

A plugin using this module shall have a module named dextool.plugin.runner;

*/
module dextool.plugin.main.standard;

import dextool.type : FileName, ExitStatusType;

/** Parse the raw command line.
 */
auto parseLogLevel(string[] args) {
    import std.algorithm : findAmong;
    import std.array : empty;
    import dextool.logger : ConfigureLog;

    return findAmong(args, ["-d", "--debug"]).empty ? ConfigureLog.info : ConfigureLog.debug_;
}

int main(string[] args) {
    import std.algorithm : filter, among;
    import std.array : array;
    import std.stdio : writeln;
    import dextool.logger : confLogLevel;

    confLogLevel(parseLogLevel(args));

    // holds the remining arguments after -d/--debug has bee removed
    auto remining_args = args.filter!(a => !a.among("-d", "--debug")).array();

    // REQUIRED BY PLUGINS USING THIS MAIN
    import dextool.plugin.runner : runPlugin;

    return runPlugin(remining_args);
}
