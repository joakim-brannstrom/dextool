/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.frontend.raw_args;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.type : Path;

import dextool.plugin.fuzzer.type : FullyQualifiedNameType, Param, Symbol, Fuzz, SequenceId;

struct RawConfiguration {
    import std.getopt : getopt, GetoptResult;

    Nullable!XmlConfig xmlConfig;

    string[] fileExclude;
    string[] fileRestrict;
    string[] testDoubleInclude;
    Path[] inFiles;
    string[] cflags;
    string[] compileDb;
    string header;
    string headerFile;
    string mainFileName = "intercept";
    string stripInclude;
    string out_;
    string config;
    bool help;
    bool helpRegex;
    bool shortPluginHelp;

    private GetoptResult help_info;

    void parse(string[] args) {
        static import std.getopt;

        string[] input;

        try {
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "compile-db", "Retrieve compilation parameters from the file", &compileDb,
                   "config", "Use configuration file", &config,
                   "file-exclude", "Exclude files from generation matching the regex", &fileExclude,
                   "file-restrict", "Restrict the scope of the test double to those files matching the regex", &fileRestrict,
                   "header", "Prepend generated files with the string", &header,
                   "header-file", "Prepend generated files with the header read from the file", &headerFile,
                   "help-regex", "Extended help for regex's used as parameters", &helpRegex,
                   "in", "Input file to parse (at least one)", &input,
                   "main-fname", "Used as part of filename for generated files [default: intercept]", &mainFileName,
                   "out", "directory for generated files [default: ./]", &out_,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "strip-incl", "A regex used to strip the include paths", &stripInclude,
                   "td-include", "User supplied includes used instead of those found", &testDoubleInclude,
                   );
            // dfmt on
            help = help_info.helpWanted;
        } catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }

        if (helpRegex)
            help = true;

        // default arguments
        if (stripInclude.length == 0) {
            stripInclude = r".*/(.*)";
            logger.trace("--strip-incl: using default regex to strip include path (basename)");
        }

        if (config.length != 0) {
            xmlConfig = readRawConfig(Path(config));
            if (xmlConfig.isNull) {
                help = true;
            } else {
                debug logger.trace(xmlConfig.get);
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
        import std.getopt : defaultGetoptPrinter;
        import std.stdio : writeln;

        defaultGetoptPrinter("Usage: dextool fuzzer [options] [--in=] [-- CFLAGS...]",
                help_info.options);

        if (helpRegex) {
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
");
        }
    }
}

/// Symbols with range data.
@safe struct Symbols {
    Symbol[FullyQualifiedNameType] syms;
    alias syms this;

    void put(Symbol data) {
        syms[data.fullyQualifiedName] = data;
    }

    Symbol* lookup(FullyQualifiedNameType fqn) {
        return fqn in syms;
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

    /// Symbols to intercept.
    Symbols symbols;
}

void logUnknownXml(T)(ref T xml, string suggestion = null) {
    import std.xml;

    xml.onStartTag[null] = (ElementParser ep) {
        logger.warning("Unknown xml element in config: ", ep.tag.toString);
        logger.warningf(suggestion.length != 0, "   did you mean '%s'", suggestion);
    };
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
    Symbols syms;

    if (auto tag = "version" in xml.tag.attr) {
        version_ = DextoolVersion(*tag);
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
    xml.onStartTag["symbols"] = (ElementParser symbols_tag) {
        symbols_tag.onStartTag["symbol"] = (ElementParser sym_tag) {
            Symbol sym;

            if (auto v = "name" in sym_tag.tag.attr) {
                sym.fullyQualifiedName = FullyQualifiedNameType(*v);
            } else {
                logger.warningf("xml-config: missing the attribute name for symbol '%s'", sym_tag.tag);
                return;
            }
            if (auto v = "filter" in sym_tag.tag.attr) {
                if (*v == "exclude")
                    sym.filter = Symbol.FilterKind.exclude;
            }
            if (auto v = "id" in sym_tag.tag.attr) {
                try {
                    sym.sequenceId = SequenceId(true, to!ulong(*v));
                } catch (ConvException ex) {
                    logger.warning("Invalid sequence id (%s) for symbol '%s': ", *v, sym_tag.tag);
                }
            }

            sym_tag.onStartTag["fuzz"] = (ElementParser e) {
                Fuzz fuzz;
                if (auto v = "use" in e.tag.attr) {
                    fuzz.use = FullyQualifiedNameType(*v);
                }
                if (auto v = "include" in e.tag.attr) {
                    fuzz.include = Path(*v);
                }

                sym.fuzz = fuzz;
                e.logUnknownXml;
            };

            sym_tag.onStartTag["param"] = (ElementParser param_tag) {
                Param p;

                if (auto v = "name" in param_tag.tag.attr) {
                    p.identifier = Param.Identifier(*v);
                }

                param_tag.onStartTag["valid"] = (ElementParser e) {
                    if (auto v = "check" in e.tag.attr) {
                        p.check = Param.Check(*v);
                    }
                    if (auto v = "condition" in e.tag.attr) {
                        p.condition = Param.Condition(*v);
                    }

                    e.logUnknownXml;
                };

                param_tag.onStartTag["fuzz"] = (ElementParser e) {
                    Fuzz fuzz;
                    if (auto v = "use" in e.tag.attr) {
                        fuzz.use = FullyQualifiedNameType(*v);
                    }
                    if (auto v = "include" in e.tag.attr) {
                        fuzz.include = Path(*v);
                    }
                    if (auto v = "param" in e.tag.attr) {
                        fuzz.param = *v;
                    }

                    p.fuzz = fuzz;
                    e.logUnknownXml;
                };

                param_tag.logUnknownXml("param");
                param_tag.parse;

                sym.limits ~= p;
            };

            sym_tag.logUnknownXml("symbol");
            sym_tag.parse;
            syms.put(sym);
        };
        symbols_tag.logUnknownXml("symbols");
        symbols_tag.parse;
    };
    // dfmt on
    xml.parse();

    return XmlConfig(version_, skip_flags, command, filter_clang_flags, syms);
}

static import dextool.xml;

alias readRawConfig = dextool.xml.readRawConfig!(XmlConfig, parseRawConfig);

/// The raw arguments from the command line.
struct RawCliArguments {
    string[] payload;
    alias payload this;
}
