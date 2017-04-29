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

import dextool.plugin.types : CliOptionParts;

static import dextool.xml;

struct RawConfiguration {
    import dextool.type : FileName;

    Nullable!XmlConfig xmlConfig;

    string[] fileExclude;
    string[] fileRestrict;
    string[] testDoubleInclude;
    string[] inFiles;
    string[] cflags;
    string[] compileDb;
    string header;
    string headerFile;
    string mainName = "TestDouble";
    string mainFileName = "test_double";
    string prefix = "Test_";
    string stripInclude;
    string out_;
    string config;
    bool doFreeFuncs;
    bool shortPluginHelp;
    bool help;
    bool gmock;
    bool generatePreInclude;
    bool genPostInclude;

    string[] originalFlags;

    void parse(string[] args) {
        import std.getopt;

        originalFlags = args.dup;

        // dfmt off
        try {
            getopt(args, std.getopt.config.keepEndOfOptions, "h|help", &help,
                   "short-plugin-help", &shortPluginHelp,
                   "main", &mainName,
                   "main-fname", &mainFileName,
                   "out", &out_,
                   "compile-db", &compileDb,
                   "prefix", &prefix,
                   "strip-incl", &stripInclude,
                   "header", &header,
                   "header-file", &headerFile,
                   "gen-free-func", &doFreeFuncs,
                   "gmock", &gmock,
                   "gen-pre-incl", &generatePreInclude,
                   "gen-post-incl", &genPostInclude,
                   "td-include", &testDoubleInclude,
                   "file-exclude", &fileExclude,
                   "file-restrict", &fileRestrict,
                   "in", &inFiles,
                   "config", &config);
        }
        catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }
        // dfmt on

        // default arguments
        if (stripInclude.length == 0) {
            stripInclude = r".*/(.*)";
            logger.trace("--strip-incl: using default regex to strip include path (basename)");
        }

        if (config.length != 0) {
            xmlConfig = readRawConfig(FileName(config));
            if (xmlConfig.isNull) {
                help = true;
            }
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    void printHelp() {
        import std.stdio : writefln;

        writefln("%s\n\n%s\n%s", cpptestdouble_opt.usage,
                cpptestdouble_opt.optional, cpptestdouble_opt.others);
    }

    void dump() {
        logger.tracef("args:
--header            :%s
--header-file       :%s
--file-restrict     :%s
--prefix            :%s
--gmock             :%s
--out               :%s
--file-exclude      :%s
--main              :%s
--strip-incl        :%s
--main-fname        :%s
--in                :%s
--compile-db        :%s
--gen-free-func     :%s
--gen-post-incl     :%s
--gen-pre-incl      :%s
--help              :%s
--td-include        :%s
--config            :%s
CFLAGS              :%s

xmlConfig           :%s", header, headerFile, fileRestrict, prefix, gmock, out_, fileExclude, mainName,
                stripInclude, mainFileName, inFiles, compileDb, doFreeFuncs, genPostInclude,
                generatePreInclude, help, testDoubleInclude, config, cflags, xmlConfig);
    }
}

// dfmt off
static auto cpptestdouble_opt = CliOptionParts(
    "usage:
 dextool cpptestdouble [options] [--in=] [-- CFLAGS...]",
    // -------------
    " --main=name        Used as part of interface, namespace etc [default: TestDouble]
 --main-fname=n     Used as part of filename for generated files [default: test_double]
 --prefix=p         Prefix used when generating test artifacts [default: Test_]
 --strip-incl=r     A regex used to strip the include paths
 --gmock            Generate a gmock implementation of test double interface
 --gen-free-func    Generate test doubles of free functions
 --gen-pre-incl     Generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    Generate a post include header file if it doesn't exist and use it
 --header=s         Prepend generated files with the string
 --header-file=f    Prepend generated files with the header read from the file
 --config=path      Use configuration file",
    // -------------
"others:
 --in=              Input file to parse
 --out=dir          directory for generated files [default: ./]
 --compile-db=j     Retrieve compilation parameters from the file
 --file-exclude=    Exclude files from generation matching the regex
 --file-restrict=   Restrict the scope of the test double to those files
                    matching the regex.
 --td-include=      User supplied includes used instead of those found

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
"
);
// dfmt on

/** Extracted configuration data from an XML file.
 *
 * It is not inteded to be used as is but rather further processed.
 */
struct XmlConfig {
    import dextool.type : DextoolVersion, RawCliArguments, FilterClangFlag;

    DextoolVersion version_;
    int skipCompilerArgs;
    RawCliArguments command;
    FilterClangFlag[] filterClangFlags;
}

auto parseRawConfig(T)(T xml) @trusted {
    import std.conv : to, ConvException;
    import std.xml;
    import dextool.utility : DextoolVersion;
    import dextool.type : RawCliArguments, FilterClangFlag;

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
