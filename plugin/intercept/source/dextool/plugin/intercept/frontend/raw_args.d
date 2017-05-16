/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.intercept.frontend.raw_args;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type;
import dextool.utility;

import dextool.plugin.types;

import dextool.plugin.intercept.type;

struct RawConfiguration {
    import std.getopt : getopt, GetoptResult;

    Nullable!XmlConfig xmlConfig;

    string[] testDoubleInclude;
    string[] inFiles;
    string[] cflags;
    string[] compileDb;
    string header;
    string headerFile;
    string mainFileName = "intercept";
    string prefix = "intercept_";
    string stripInclude;
    string out_;
    string config;
    bool help;
    bool shortPluginHelp;

    private GetoptResult help_info;

    void parse(string[] args) {
        static import std.getopt;

        try {
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "main-fname", "Used as part of filename for generated files [default: intercept]", &mainFileName,
                   "out", "directory for generated files [default: ./]", &out_,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "prefix", "Prefix all function calls to the intercepted target [default: intercept_]", &prefix,
                   "strip-incl", "A regex used to strip the include paths", &stripInclude,
                   "header", "Prepend generated files with the string", &header,
                   "header-file", "Prepend generated files with the header read from the file", &headerFile,
                   "td-include", "User supplied includes used instead of those found", &testDoubleInclude,
                   "in", "Input file to parse (at least one)", &inFiles,
                   "config", "Use configuration file", &config);
            // dfmt on
            help = help_info.helpWanted;
        }
        catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }

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
        import std.getopt : defaultGetoptPrinter;
        import std.stdio : writeln;

        defaultGetoptPrinter("Usage: dextool intercept [options] [--in=] [-- CFLAGS...]",
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
");
    }
}

/// Symbols to intercept.
@safe struct Symbols {
    InterceptSymbol[SymbolName] syms;
    alias syms this;

    bool contains(string symbol) {
        if (SymbolName(symbol) in syms)
            return true;
        return false;
    }

    bool hasSymbols() {
        return syms.length != 0;
    }

    void put(InterceptSymbol data) {
        syms[data.funcName] = data;
    }
}

/// A symbol to intercept.
@safe struct InterceptSymbol {
    SymbolName funcName;
    string prefix;
}

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

    /// Symbols to intercept.
    Symbols symbols;
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
    Symbols syms;

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
    xml.onStartTag["intercept"] = (ElementParser filter_sym) {
        xml.onEndTag["func"] = (const Element e) {
            if (auto pref = "prefix" in e.tag.attr) {
                auto sym = InterceptSymbol(SymbolName(e.text), *pref);
                syms.put(sym);
            } else {
                logger.warningf("xml-config: missing the attribute prefix for intercept func '%s'", e.text);
            }
        };
    };
    // dfmt on
    xml.parse();

    return XmlConfig(version_, skip_flags, command, filter_clang_flags, syms);
}

static import dextool.xml;

alias readRawConfig = dextool.xml.readRawConfig!(XmlConfig, parseRawConfig);
