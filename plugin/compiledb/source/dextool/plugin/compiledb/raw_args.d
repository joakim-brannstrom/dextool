/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.compiledb.raw_args;

import logger = std.experimental.logger;

struct RawConfiguration {
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;

    string out_ = "./";

    string[] inCompileDb;

    bool help;
    bool shortPluginHelp;

    private GetoptResult help_info;

    void parse(string[] args) {
        static import std.getopt;

        try {
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                    "short-plugin-help", "short description of the plugin",
                    &shortPluginHelp, "out",
                    "directory/file do write output to [default: ./]", &out_,);
            help = help_info.helpWanted;
        } catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }

        if (args.length > 2) {
            // the first is the binary itself
            inCompileDb = args[1 .. $];
        }
    }

    void printHelp() {
        defaultGetoptPrinter("Usage: dextool compiledb [options] --out=FILE DBFILE0 DBFILE1...",
                help_info.options);
    }
}
