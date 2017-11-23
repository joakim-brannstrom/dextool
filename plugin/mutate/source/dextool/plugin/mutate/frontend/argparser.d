/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.frontend.argparser;

import logger = std.experimental.logger;

@safe:

/// Represent a yes/no configuration option.
/// Using an explicit name so the help text is improved in such a way that the
/// user understand that the choices are between yes/no.
enum YesNo {
    no,
    yes
}

/// The kind of mutation to perform
enum Mutation {
    /// Relational operator replacement
    ror,
    /// Logical connector replacement
    lcr,
    /// Arithmetic operator replacement
    aor,
    /// Unary operator insert
    uoi,
    /// Absolute value replacement
    abs,
}

struct ArgParser {
    import std.typecons : Nullable;
    import std.conv : ConvException;
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;
    import dextool.type : FileName;

    string[] inFiles;
    string[] cflags;
    string[] compileDb;

    string outputDirectory;

    bool help;
    bool shortPluginHelp;

    Nullable!size_t mutationPoint;

    Mutation mutation;

    private GetoptResult help_info;
    private string cli_mutation_point;

    /**
     * trusted: getopt is safe in dmd-2.077.0.
     * Remove the trusted attribute when upgrading the minimal required version
     * of the D frontend.
     */
    void parse(string[] args) @trusted {
        import std.traits : EnumMembers;
        import std.format : format;

        static import std.getopt;

        try {
            // dfmt off
            // sort alphabetic
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "in", "Input file to parse (at least one)", &inFiles,
                   "out", "directory for generated files [default: ./]", &outputDirectory,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "mutation", "kind of mutation to perform " ~ format("[%(%s|%)]", [EnumMembers!Mutation]), &mutation,
                   "mutation-point", "the mutation point to change", &cli_mutation_point,
                   );
            // dfmt on

            try {
                import std.conv : to;

                if (cli_mutation_point.length != 0)
                    mutationPoint = cli_mutation_point.to!size_t;
            }
            catch (ConvException e) {
                logger.infof("invalid mutation point '%s'. It must be in the range [0, %s]",
                        cli_mutation_point, size_t.max);
            }

            help = help_info.helpWanted;
        }
        catch (ConvException e) {
            logger.error(e.msg);
            logger.errorf("%s possible values: %(%s|%)", Mutation.stringof,
                    [EnumMembers!Mutation]);
            help = true;
        }
        catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }
        catch (Exception ex) {
            logger.error(ex.msg);
            help = true;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    /**
     * Trusted:
     * The only input is a static string and data derived from getopt itselt.
     * Assuming that getopt in phobos behave well.
     */
    void printHelp() @trusted {
        defaultGetoptPrinter("Usage: dextool mutate [options] [--in=] [-- CFLAGS...]",
                help_info.options);
    }
}
