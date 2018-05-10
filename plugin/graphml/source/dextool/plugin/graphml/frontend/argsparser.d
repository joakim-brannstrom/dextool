/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.graphml.frontend.argsparser;

import logger = std.experimental.logger;

@safe:

struct RawConfiguration {
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;

    string[] cflags;
    string[] compileDb;
    string[] fileExclude;
    string[] fileRestrict;
    string[] inFiles;
    string filePrefix = "dextool_";
    string out_;
    bool classInheritDep;
    bool classMemberDep;
    bool classMethod;
    bool classParamDep;
    bool help;
    bool shortPluginHelp;
    bool skipFileError;

    string[] originalFlags;

    private GetoptResult help_info;

    void parse(string[] args) {
        import std.getopt;

        originalFlags = args.dup;

        try {
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
               "class-method", &classMethod,
               "class-paramdep", &classParamDep,
               "class-inheritdep", &classInheritDep,
               "class-memberdep", &classMemberDep,
               "compile-db", &compileDb,
               "file-exclude", &fileExclude,
               "file-prefix", &filePrefix,
               "file-restrict", &fileRestrict,
               "in", &inFiles,
               "out", &out_,
               "short-plugin-help", &shortPluginHelp,
               "skip-file-error", &skipFileError,
               );
            // dfmt on

            help = help_info.helpWanted;
        } catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        } catch (Exception ex) {
            logger.error(ex.msg);
            help = true;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    void printHelp() @trusted {
        defaultGetoptPrinter("Usage: dextool mutate [options] [--in=] [-- CFLAGS...]",
                help_info.options);
    }
}
