/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.ctestdouble.frontend.ctestdouble;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import cpptooling.type;
import dextool.compilation_db;
import dextool.type;

import dextool.plugin.types;
import dextool.plugin.ctestdouble.backend.cvariant : Controller, Parameters, Products;
import dextool.plugin.ctestdouble.frontend.types;
import dextool.plugin.ctestdouble.frontend.xml;

// workaround for ldc-1.1.0 and dmd-2.071.2
auto workaround_linker_error() {
    import cpptooling.testdouble.header_filter : TestDoubleIncludes,
        GenericTestDoubleIncludes, DummyPayload;

    return typeid(GenericTestDoubleIncludes!DummyPayload).toString();
}

struct RawConfiguration {
    Nullable!XmlConfig xmlConfig;

    string[] fileExclude;
    string[] fileRestrict;
    string[] testDoubleInclude;
    Path[] inFiles;
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
    bool help;
    bool shortPluginHelp;
    bool gmock;
    bool generatePreInclude;
    bool genPostInclude;
    bool locationAsComment;
    bool generateZeroGlobals;
    bool invalidXmlConfig;

    string[] originalFlags;

    void parse(string[] args) {
        import std.getopt;

        originalFlags = args.dup;
        string[] input;

        try {
            bool no_zero_globals;
            // dfmt off
            getopt(args, std.getopt.config.keepEndOfOptions, "h|help", &help,
                   "compile-db", &compileDb,
                   "config", &config,
                   "file-exclude", &fileExclude,
                   "file-restrict", &fileRestrict,
                   "gen-post-incl", &genPostInclude,
                   "gen-pre-incl", &generatePreInclude,
                   "gmock", &gmock,
                   "header", &header,
                   "header-file", &headerFile,
                   "in", &input,
                   "loc-as-comment", &locationAsComment,
                   "main", &mainName,
                   "main-fname", &mainFileName,
                   "no-zeroglobals", &no_zero_globals,
                   "out", &out_,
                   "prefix", &prefix,
                   "short-plugin-help", &shortPluginHelp,
                   "strip-incl", &stripInclude,
                   "td-include", &testDoubleInclude);
            // dfmt on
            generateZeroGlobals = !no_zero_globals;
        } catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }

        // default arguments
        if (stripInclude.length == 0) {
            stripInclude = r".*/(.*)";
            logger.trace("--strip-incl: using default regex to strip include path (basename)");
        }

        if (config.length != 0) {
            xmlConfig = readRawConfig(Path(config));
            if (xmlConfig.isNull) {
                invalidXmlConfig = true;
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
        import std.stdio : writefln;

        writefln("%s\n\n%s\n%s", ctestdouble_opt.usage,
                ctestdouble_opt.optional, ctestdouble_opt.others);
    }

    void dump() {
        // TODO remove this
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
--gen-post-incl     :%s
--gen-pre-incl      :%s
--help              :%s
--loc-as-comment    :%s
--td-include        :%s
--no-zeroglobals    :%s
--config            :%s
CFLAGS              :%s

xmlConfig           :%s", header, headerFile, fileRestrict, prefix, gmock,
                out_, fileExclude, mainName, stripInclude,
                mainFileName, inFiles, compileDb, genPostInclude, generatePreInclude, help, locationAsComment,
                testDoubleInclude, !generateZeroGlobals, config, cflags, xmlConfig);
    }
}

// dfmt off
static auto ctestdouble_opt = CliOptionParts(
    "usage:
 dextool ctestdouble [options] [--in=] [-- CFLAGS]",
    // -------------
    " --main=name        Used as part of interface, namespace etc [default: TestDouble]
 --main-fname=n     Used as part of filename for generated files [default: test_double]
 --prefix=p         Prefix used when generating test artifacts [default: Test_]
 --strip-incl=r     A regexp used to strip the include paths
 --gmock            Generate a gmock implementation of test double interface
 --gen-pre-incl     Generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    Generate a post include header file if it doesn't exist and use it
 --loc-as-comment   Generate a comment containing the location the symbol was derived from.
                    Makes it easier to correctly define excludes/restricts
 --header=s         Prepend generated files with the string
 --header-file=f    Prepend generated files with the header read from the file
 --no-zeroglobals   Turn off generation of the default implementation that zeroes globals
 --config=path      Use configuration file",
    // -------------
"others:
 --in=              Input file to parse
 --out=dir          directory for generated files [default: ./]
 --compile-db=      Retrieve compilation parameters from the file
 --file-exclude=    Exclude files from generation matching the regex
 --file-restrict=   Restrict the scope of the test double to those files
                    matching the regex
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

EXAMPLES

Generate a simple C test double.
  dextool ctestdouble functions.h

  Analyze and generate a test double for function prototypes and extern variables.
  Both those found in functions.h and outside, aka via includes.

  The test double is written to ./test_double.hpp/.cpp.
  The name of the interface is Test_Double.

Generate a C test double excluding data from specified files.
  dextool ctestdouble --file-exclude=/foo.h --file-exclude='functions.[h,c]' --out=outdata/ functions.h -- -DBAR -I/some/path

  The code analyzer (Clang) will be passed the compiler flags -DBAR and -I/some/path.
  During generation declarations found in foo.h or functions.h will be excluded.

  The file holding the test double is written to directory outdata.
"
);
// dfmt on

struct FileData {
    import dextool.io : WriteStrategy;
    import dextool.type : Path;

    Path filename;
    string data;
    WriteStrategy strategy;
}

/** Test double generation of C code.
 *
 * TODO Describe the options.
 */
class CTestDoubleVariant : Controller, Parameters, Products {
    import std.regex : regex, Regex;
    import std.typecons : Flag;
    import dextool.compilation_db : CompileCommandFilter;
    import cpptooling.testdouble.header_filter : TestDoubleIncludes, LocationType;
    import dsrcgen.cpp : CppModule, CppHModule;

    private {
        static const hdrExt = ".hpp";
        static const implExt = ".cpp";
        static const xmlExt = ".xml";

        StubPrefix prefix;

        Path output_dir;
        Path main_file_hdr;
        Path main_file_impl;
        Path main_file_globals;
        Path gmock_file;
        Path pre_incl_file;
        Path post_incl_file;
        Path config_file;
        Path log_file;
        CustomHeader custom_hdr;

        MainName main_name;
        MainNs main_ns;
        MainInterface main_if;
        Flag!"Gmock" gmock;
        Flag!"PreInclude" pre_incl;
        Flag!"PostInclude" post_incl;
        Flag!"locationAsComment" loc_as_comment;
        Flag!"generateZeroGlobals" generate_zero_globals;

        Nullable!XmlConfig xmlConfig;
        CompileCommandFilter compiler_flag_filter;
        FilterSymbol restrict_symbols;
        FilterSymbol exclude_symbols;

        Regex!char[] exclude;
        Regex!char[] restrict;

        /// Data produced by the generatore intented to be written to specified file.
        FileData[] file_data;

        TestDoubleIncludes td_includes;
    }

    static auto makeVariant(ref RawConfiguration args) {
        // dfmt off
        auto variant = new CTestDoubleVariant(
                MainFileName(args.mainFileName), Path(args.out_),
                regex(args.stripInclude))
            .argPrefix(args.prefix)
            .argMainName(args.mainName)
            .argLocationAsComment(args.locationAsComment)
            .argGmock(args.gmock)
            .argPreInclude(args.generatePreInclude)
            .argPostInclude(args.genPostInclude)
            .argForceTestDoubleIncludes(args.testDoubleInclude)
            .argFileExclude(args.fileExclude)
            .argFileRestrict(args.fileRestrict)
            .argCustomHeader(args.header, args.headerFile)
            .argGenerateZeroGlobals(args.generateZeroGlobals)
            .argXmlConfig(args.xmlConfig);
        // dfmt on

        return variant;
    }

    /** Design of c'tor.
     *
     * The c'tor has as paramters all the required configuration data.
     * Assignment of members are used for optional configuration.
     *
     * Follows the design pattern "correct by construction".
     *
     * TODO document the parameters.
     */
    this(MainFileName main_fname, Path output_dir, Regex!char strip_incl) {
        this.output_dir = output_dir;
        this.td_includes = TestDoubleIncludes(strip_incl);

        import std.path : baseName, buildPath, stripExtension;

        string base_filename = cast(string) main_fname;

        this.main_file_hdr = Path(buildPath(cast(string) output_dir, base_filename ~ hdrExt));
        this.main_file_impl = Path(buildPath(cast(string) output_dir, base_filename ~ implExt));
        this.main_file_globals = Path(buildPath(cast(string) output_dir,
                base_filename ~ "_global" ~ implExt));
        this.gmock_file = Path(buildPath(cast(string) output_dir, base_filename ~ "_gmock" ~ hdrExt));
        this.pre_incl_file = Path(buildPath(cast(string) output_dir,
                base_filename ~ "_pre_includes" ~ hdrExt));
        this.post_incl_file = Path(buildPath(cast(string) output_dir,
                base_filename ~ "_post_includes" ~ hdrExt));
        this.config_file = Path(buildPath(output_dir, base_filename ~ "_config" ~ xmlExt));
        this.log_file = Path(buildPath(output_dir, base_filename ~ "_log" ~ xmlExt));
    }

    auto argFileExclude(string[] a) {
        import std.array : array;
        import std.algorithm : map;

        this.exclude = a.map!(a => regex(a)).array();
        return this;
    }

    auto argFileRestrict(string[] a) {
        import std.array : array;
        import std.algorithm : map;

        this.restrict = a.map!(a => regex(a)).array();
        return this;
    }

    auto argPrefix(string s) {
        this.prefix = StubPrefix(s);
        return this;
    }

    auto argMainName(string s) {
        this.main_name = MainName(s);
        this.main_ns = MainNs(s);
        this.main_if = MainInterface("I_" ~ s);
        return this;
    }

    /// Force the includes to be those supplied by the user.
    auto argForceTestDoubleIncludes(string[] a) {
        if (a.length != 0) {
            td_includes.forceIncludes(a);
        }
        return this;
    }

    auto argCustomHeader(string header, string header_file) {
        if (header.length != 0) {
            this.custom_hdr = CustomHeader(header);
        } else if (header_file.length != 0) {
            import std.file : readText;

            string content = readText(header_file);
            this.custom_hdr = CustomHeader(content);
        }

        return this;
    }

    auto argGmock(bool a) {
        this.gmock = cast(Flag!"Gmock") a;
        return this;
    }

    auto argPreInclude(bool a) {
        this.pre_incl = cast(Flag!"PreInclude") a;
        return this;
    }

    auto argPostInclude(bool a) {
        this.post_incl = cast(Flag!"PostInclude") a;
        return this;
    }

    auto argLocationAsComment(bool a) {
        this.loc_as_comment = cast(Flag!"locationAsComment") a;
        return this;
    }

    auto argGenerateZeroGlobals(bool value) {
        this.generate_zero_globals = cast(Flag!"generateZeroGlobals") value;
        return this;
    }

    /** Ensure that the relevant information from the xml file is extracted.
     *
     * May overwrite information from the command line.
     * TODO or should the command line have priority over the xml file?
     */
    auto argXmlConfig(Nullable!XmlConfig conf) {
        import dextool.compilation_db : defaultCompilerFlagFilter;

        if (conf.isNull) {
            compiler_flag_filter = CompileCommandFilter(defaultCompilerFlagFilter, 0);
            return this;
        }

        xmlConfig = conf;
        compiler_flag_filter = CompileCommandFilter(conf.get.filterClangFlags,
                conf.get.skipCompilerArgs);
        restrict_symbols = conf.get.restrictSymbols;
        exclude_symbols = conf.get.excludeSymbols;

        return this;
    }

    void processIncludes() {
        td_includes.process();
    }

    void finalizeIncludes() {
        td_includes.finalize();
    }

    /// Destination of the configuration file containing how the test double was generated.
    Path getXmlConfigFile() {
        return config_file;
    }

    /** Destination of the xml log for how dextool was ran when generatinng the
     * test double.
     */
    Path getXmlLog() {
        return log_file;
    }

    ref FilterSymbol getRestrictSymbols() {
        return restrict_symbols;
    }

    ref FilterSymbol getExcludeSymbols() {
        return exclude_symbols;
    }

    ref CompileCommandFilter getCompileCommandFilter() {
        return compiler_flag_filter;
    }

    /// Data produced by the generatore intented to be written to specified file.
    ref FileData[] getProducedFiles() {
        return file_data;
    }

    void putFile(Path fname, string data) {
        file_data ~= FileData(fname, data);
    }

    // -- Controller --

    bool doFile(in string filename, in string info) {
        import dextool.plugin.regex_matchers : matchAny;

        bool restrict_pass = true;
        bool exclude_pass = true;

        if (restrict.length > 0) {
            restrict_pass = matchAny(filename, restrict);
            debug {
                logger.tracef(!restrict_pass, "--file-restrict skipping %s", info);
            }
        }

        if (exclude.length > 0) {
            exclude_pass = !matchAny(filename, exclude);
            debug {
                logger.tracef(!exclude_pass, "--file-exclude skipping %s", info);
            }
        }

        return restrict_pass && exclude_pass;
    }

    bool doSymbol(string symbol) {
        // fast path, assuming no symbol filter is the most common
        if (!restrict_symbols.hasSymbols && !exclude_symbols.hasSymbols) {
            return true;
        }

        if (restrict_symbols.hasSymbols && exclude_symbols.hasSymbols) {
            return restrict_symbols.contains(symbol) && !exclude_symbols.contains(symbol);
        }

        if (restrict_symbols.hasSymbols) {
            return restrict_symbols.contains(symbol);
        }

        if (exclude_symbols.hasSymbols) {
            return !exclude_symbols.contains(symbol);
        }

        return true;
    }

    bool doGoogleMock() {
        return gmock;
    }

    bool doPreIncludes() {
        import std.file : exists;

        return pre_incl && !exists(cast(string) pre_incl_file);
    }

    bool doIncludeOfPreIncludes() {
        return pre_incl;
    }

    bool doPostIncludes() {
        import std.file : exists;

        return post_incl && !exists(cast(string) post_incl_file);
    }

    bool doIncludeOfPostIncludes() {
        return post_incl;
    }

    bool doLocationAsComment() {
        return loc_as_comment;
    }

    // -- Parameters --

    Path[] getIncludes() {
        import std.algorithm : map;
        import std.array : array;

        return td_includes.includes.map!(a => Path(a)).array();
    }

    Path getOutputDirectory() {
        return output_dir;
    }

    Parameters.Files getFiles() {
        return Parameters.Files(main_file_hdr, main_file_impl,
                main_file_globals, gmock_file, pre_incl_file, post_incl_file);
    }

    MainName getMainName() {
        return main_name;
    }

    MainNs getMainNs() {
        return main_ns;
    }

    MainInterface getMainInterface() {
        return main_if;
    }

    StubPrefix getFilePrefix() {
        return StubPrefix("");
    }

    StubPrefix getArtifactPrefix() {
        return prefix;
    }

    DextoolVersion getToolVersion() {
        import dextool.utility : dextoolVersion;

        return dextoolVersion;
    }

    CustomHeader getCustomHeader() {
        return custom_hdr;
    }

    Flag!"generateZeroGlobals" generateZeroGlobals() {
        return generate_zero_globals;
    }

    // -- Products --

    void putFile(Path fname, CppHModule hdr_data) {
        file_data ~= FileData(fname, hdr_data.render());
    }

    void putFile(Path fname, CppModule impl_data) {
        file_data ~= FileData(fname, impl_data.render());
    }

    void putLocation(Path fname, LocationType type) {
        td_includes.put(fname, type);
    }
}

/// TODO refactor, doing too many things.
ExitStatusType genCstub(CTestDoubleVariant variant, in string[] in_cflags,
        CompileCommandDB compile_db, Path[] in_files) {
    import std.typecons : Yes;

    import dextool.clang : findFlags;
    import dextool.compilation_db : ParseData = SearchResult;
    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.io : writeFileData;
    import dextool.plugin.ctestdouble.backend.cvariant : CVisitor, Generator;
    import dextool.utility : prependDefaultFlags, PreferLang, analyzeFile;

    const user_cflags = prependDefaultFlags(in_cflags, PreferLang.c);
    const total_files = in_files.length;
    auto visitor = new CVisitor(variant, variant);
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto generator = Generator(variant, variant, variant);

    foreach (idx, in_file; in_files) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        ParseData pdata;

        // TODO duplicate code in c, c++ and plantuml. Fix it.
        if (compile_db.length > 0) {
            auto tmp = compile_db.findFlags(Path(in_file), user_cflags,
                    variant.getCompileCommandFilter);
            if (tmp.isNull) {
                return ExitStatusType.Errors;
            }
            pdata = tmp.get;
        } else {
            pdata.flags.prependCflags(user_cflags.dup);
            pdata.absoluteFile = AbsolutePath(Path(in_file));
        }

        if (analyzeFile(pdata.absoluteFile, pdata.cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        generator.aggregate(visitor.root, visitor.container);
        visitor.clearRoot;
        variant.processIncludes;
    }

    variant.finalizeIncludes;

    // Analyse and generate test double
    generator.process(visitor.container);

    debug {
        logger.trace(visitor);
    }

    return writeFileData(variant.getProducedFiles);
}
