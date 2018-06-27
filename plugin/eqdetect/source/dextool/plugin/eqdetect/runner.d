/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains an example plugin that demonstrate how to:
 - interact with the clang AST
 - print the AST nodes when debugging is activated by the user via the command line
 - find all free functions and generate a dummy implementation.

It is purely intended as an example to get started developing **your** plugin.
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

    import dextool.plugin.eqdetect.subfolder : ForFinder;
    import std.conv : to;

    ForFinder ff;
    ff.search(to!string(pargs.file));

    /*import std.file;
    import std.conv : to;
    import std.algorithm : canFind;

    File file = File(to!string(pargs.file), "r");
    int i = 1;
    while (!file.eof()) {
        string s = file.readln();
        if(canFind(s, "for") && !canFind(s, "//")){
        writeln(to!string(i) ~ s);
        }
        i++;
    }

    file.close();*/

    return ExitStatusType.Ok;
}

/** Handle parsing of user arguments.

For a simple plugin this is overly complex. But a plugin very seldom stays
simple. By keeping the user input parsing and validation separate from the rest
of the program it become more robust to future changes.
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
