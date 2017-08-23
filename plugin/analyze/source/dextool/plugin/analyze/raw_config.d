/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.analyze.raw_config;

import logger = std.experimental.logger;

/** Handle parsing of user arguments.

For a simple plugin this is overly complex. But a plugin very seldom stays
simple. By keeping the user input parsing and validation separate from the rest
of the program it become more robust to future changes.
*/
struct RawConfiguration {
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;

    bool help;
    bool errorHelp;
    bool shortPluginHelp;
    bool mccabe;
    bool outputJson;
    bool outputStdout;
    int mccabeThreshold = 5;
    int workerThreads = -1;
    string outdir = ".";
    string restrictDir = ".";
    string[] cflags;
    string[] compileDb;
    string[] files;

    private GetoptResult help_info;

    void parse(string[] args) @safe {
        static import std.getopt;

        try {
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "threads", "number of worker threads to use (default: detected CPU cores)", &workerThreads,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "output-json", "Write the analyze result to json file(s)", &outputJson,
                   "output-stdout", "Write the analyze result to stdout", &outputStdout,
                   "restrict", "Restrict analyze of files to those in this directory tree (default: .)", &restrictDir,
                   "mccabe", "Calculate the McCabe complexity of functions and files", &mccabe,
                   "mccabe-threshold", "Threshold that must be reached for the McCabe value to be reported (default: 5)", &mccabeThreshold,
                   "out", "directory to write result files to (default: .)", &outdir,
                   "in", "Input file to parse", &files,
                   );
            // dfmt on
            help = help_info.helpWanted;
        }
        catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            errorHelp = true;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();

        if (!shortPluginHelp) {
            // DMD-2.075.0
            // workaround because the log is funky. those from
            // application.plugin.toPlugin aren't "flushed". It think it is
            // because pipeProcess uses linux pipes and this somehow interacts
            // badly with std.experimental.logger;
            debug logger.trace("");

            debug logger.trace(this);
        }
    }

    void printHelp() @trusted {
        import std.stdio : writeln;

        defaultGetoptPrinter("Usage: dextool analyze [options] [--in=] [-- CFLAGS...]",
                help_info.options);
    }
}
