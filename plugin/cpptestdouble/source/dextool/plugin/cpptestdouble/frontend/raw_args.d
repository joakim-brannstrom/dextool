/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.cpptestdouble.frontend.raw_args;

import std.typecons : Nullable;

import logger = std.experimental.logger;

static import dextool.xml;

/// Represent a yes/no configuration option.
/// Using an explicit name so the help text is improved in such a way that the
/// user understand that the choices are between yes/no.
enum Config_YesNo {
    no,
    yes
}

struct RawConfiguration {
    import std.conv : ConvException;
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;
    import dextool.type : Path;

    Nullable!XmlConfig xmlConfig;

    Config_YesNo gtestPODPrettyPrint = Config_YesNo.yes;
    Path[] inFiles;
    bool doFreeFuncs;
    bool genPostInclude;
    bool generatePreInclude;
    bool gmock;
    bool help;
    bool shortPluginHelp;
    string config;
    string header;
    string headerFile;
    string mainFileName = "test_double";
    string mainName = "TestDouble";
    string out_;
    string prefix = "Test_";
    string stripInclude;
    string systemCompiler;
    string[] cflags;
    string[] compileDb;
    string[] fileExclude;
    string[] fileRestrict;
    string[] testDoubleInclude;

    string[] originalFlags;

    private GetoptResult help_info;

    void parse(string[] args) {
        import std.traits : EnumMembers;
        import std.format : format;

        static import std.getopt;

        originalFlags = args.dup;
        string[] input;

        try {
            // dfmt off
            // sort alphabetic
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "config", "Use configuration file", &config,
                   "file-exclude", "Exclude files from generation matching the regex", &fileExclude,
                   "file-restrict", "Restrict the scope of the test double to those files matching the regex.", &fileRestrict,
                   "free-func", "Generate test doubles of free functions", &doFreeFuncs,
                   "gen-post-incl", "Generate a post include header file if it doesn't exist and use it", &genPostInclude,
                   "gen-pre-incl", "Generate a pre include header file if it doesn't exist and use it", &generatePreInclude,
                   "gmock", "Generate a gmock implementation of test double interface", &gmock,
                   "gtest-pp", "Generate pretty printer of POD's public members for gtest " ~ format("[%(%s|%)]", [EnumMembers!Config_YesNo]), &gtestPODPrettyPrint,
                   "header", "Prepends generated files with the string", &header,
                   "header-file", "Prepend generated files with the header read from the file", &headerFile,
                   "in", "Input file to parse (at least one)", &input,
                   "main", "Used as part of interface, namespace etc [default: TestDouble]", &mainName,
                   "main-fname", "Used as part of filename for generated files [default: test_double]", &mainFileName,
                   "out", "directory for generated files [default: ./]", &out_,
                   "prefix", "Prefix used when generating test artifacts [default: Test_]", &prefix,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "strip-incl", "A regex used to strip the include paths", &stripInclude,
                   "system-compiler", "Derive the system include paths from this compiler [default: use from compile_commands.json]", &systemCompiler,
                   "td-include", "User supplied includes used instead of those found", &testDoubleInclude,
                   );
            // dfmt on
            help = help_info.helpWanted;
        } catch (ConvException e) {
            logger.error(e.msg);
            logger.errorf("%s possible values: %(%s|%)", Config_YesNo.stringof,
                    [EnumMembers!Config_YesNo]);
            help = true;
        } catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        } catch (Exception ex) {
            logger.error(ex.msg);
            help = true;
        }

        // default arguments
        if (stripInclude.length == 0) {
            stripInclude = r".*/(.*)";
        }

        if (config.length != 0) {
            xmlConfig = readRawConfig(Path(config));
            if (xmlConfig.isNull) {
                help = true;
            }
        }

        import std.algorithm : find, map;
        import std.array : array;
        import std.range : drop;

        inFiles = input.map!(a => Path(a)).array;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    void printHelp() {
        import std.stdio : writeln;

        defaultGetoptPrinter("Usage: dextool cpptestdouble [options] [--in=] [-- CFLAGS...]",
                help_info.options);

        writeln("
REGEX
The regex syntax is found at http://dlang.org/phobos/std_regex.html

Information about --strip-incl.
  Default regexp is: .*/(.*)

  To allow the user to selectively extract parts of the include path dextool
  applies the regex and then concatenates all the matcher groups found.  It is
  turned into the replacement include path.

  Important to remember then is that this approach requires that at least one
  matcher group exists.

Information about --file-exclude.
  The regex must fully match the filename the AST node is located in.
  If it matches all data from the file is excluded from the generated code.

Information about --file-restrict.
  The regex must fully match the filename the AST node is located in.
  Only symbols from files matching the restrict affect the generated test double.

Information about --in.
  When it is used in conjuction with a compile commands database it is used to also find the flags.
  For each entry in the database the argument to --in is matched against the file or output JSON attribute.
  If either of them match the compiler flags for that file are used.
  The argument can be either the absolute path, the exact file or output attribute or a file glob pattern.
  A glob pattern is such as `ls *.cpp`.
");
    }
}

/** Extracted configuration data from an XML file.
 *
 * It is not inteded to be used as is but rather further processed.
 */
struct XmlConfig {
    import dextool.type : DextoolVersion, FilterClangFlag;

    DextoolVersion version_;
    int skipCompilerArgs;
    RawCliArguments command;
    FilterClangFlag[] filterClangFlags;
}

auto parseRawConfig(T)(T xml) @trusted {
    import std.conv : to, ConvException;
    import std.xml;
    import dextool.utility : DextoolVersion;
    import dextool.type : FilterClangFlag;

    DextoolVersion version_;
    int skip_flags = 1;
    RawCliArguments command;
    FilterClangFlag[] filter_clang_flags;

    if (auto tag = "version" in xml.tag.attr) {
        version_ = *tag;
    }

    // dfmt off
    xml.onStartTag["compiler_flag_filter"] = (ElementParser filter_flags) {
        if (auto tag = "skip_compiler_args" in xml.tag.attr) {
            try {
                skip_flags = (*tag).to!int;
            }
            catch (ConvException ex) {
                logger.info(ex.msg);
                logger.info("   using fallback '1'");
            }
        }

        xml.onEndTag["exclude"] = (const Element e) { filter_clang_flags ~= FilterClangFlag(e.text()); };
    };
    // dfmt on
    xml.parse();

    return XmlConfig(version_, skip_flags, command, filter_clang_flags);
}

alias readRawConfig = dextool.xml.readRawConfig!(XmlConfig, parseRawConfig);

/// The raw arguments from the command line.
struct RawCliArguments {
    string[] payload;
    alias payload this;
}
