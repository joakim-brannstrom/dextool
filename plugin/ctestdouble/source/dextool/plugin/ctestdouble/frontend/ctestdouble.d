/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.ctestdouble.frontend.ctestdouble;

import logger = std.experimental.logger;
import std.algorithm : find, map;
import std.array : array, empty;
import std.range : drop;
import std.typecons : Nullable, Tuple;

import cpptooling.type;
import dextool.compilation_db;
import dextool.type;

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
    string[] fileInclude;
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
    string systemCompiler = "/usr/bin/cc";
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
                   "file-include", &fileInclude,
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
                   "system-compiler", "Derive the system include paths from this compiler [default /usr/bin/cc]", &systemCompiler,
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
--file-include      :%s
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

xmlConfig           :%s", header, headerFile, fileInclude, prefix, gmock,
                out_, fileExclude, mainName, stripInclude,
                mainFileName, inFiles, compileDb, genPostInclude, generatePreInclude, help, locationAsComment,
                testDoubleInclude, !generateZeroGlobals, config, cflags, xmlConfig);
    }
}

// dfmt off
static auto ctestdouble_opt = Tuple!(string, "usage", string, "optional", string, "others")(
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
                    Makes it easier to correctly define excludes/includes
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
 --file-include=    Restrict the scope of the test double to those files
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

Information about --file-include.
  The regex must fully match the filename the AST node is located in.
  Only symbols from files matching the include affect the generated test double.

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
    import my.filter : ReFilter;
    import dsrcgen.cpp : CppModule, CppHModule;
    import dextool.compilation_db : CompileCommandFilter;
    import cpptooling.testdouble.header_filter : TestDoubleIncludes, LocationType;

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

        string system_compiler;

        Nullable!XmlConfig xmlConfig;
        CompileCommandFilter compiler_flag_filter;
        FilterSymbol restrict_symbols;
        FilterSymbol exclude_symbols;

        string[] exclude;
        string[] include;
        ReFilter fileFilter;

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
            .argFileInclude(args.fileInclude)
            .argCustomHeader(args.header, args.headerFile)
            .argGenerateZeroGlobals(args.generateZeroGlobals)
            .argXmlConfig(args.xmlConfig)
            .systemCompiler(args.systemCompiler);
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
        this.exclude = a;
        fileFilter = ReFilter(include, exclude);
        return this;
    }

    auto argFileInclude(string[] a) {
        this.include = a;
        fileFilter = ReFilter(include, exclude);
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

    auto systemCompiler(string a) {
        this.system_compiler = a;
        return this;
    }

    // -- Controller --

    bool doFile(in string filename, in string info) {
        return fileFilter.match(filename, (string s, string type) {
            logger.tracef("matcher --file-%s removed %s. Skipping", s, type);
        });
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

    Compiler getSystemCompiler() const {
        return Compiler(system_compiler);
    }

    Compiler getMissingFileCompiler() const {
        if (system_compiler.empty)
            return Compiler("/usr/bin/cc");
        return getSystemCompiler();
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
ExitStatusType genCstub(CTestDoubleVariant variant, string[] userCflags,
        CompileCommandDB compile_db, Path[] inFiles) {
    import std.typecons : Yes;

    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.clang : reduceMissingFiles;
    import dextool.compilation_db : limitOrAllRange, parse, prependFlags,
        addCompiler, replaceCompiler, addSystemIncludes, fileRange;
    import dextool.io : writeFileData;
    import dextool.plugin.ctestdouble.backend.cvariant : CVisitor, Generator;
    import dextool.utility : prependDefaultFlags, PreferLang, analyzeFile;

    auto visitor = new CVisitor(variant, variant);
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto generator = Generator(variant, variant, variant);

    auto compDbRange() {
        if (compile_db.empty) {
            return fileRange(inFiles, variant.getMissingFileCompiler);
        }
        return compile_db.fileRange;
    }

    auto fixedDb = compDbRange.parse(variant.getCompileCommandFilter)
        .addCompiler(variant.getMissingFileCompiler).replaceCompiler(
                variant.getSystemCompiler).addSystemIncludes.prependFlags(
                prependDefaultFlags(userCflags, PreferLang.c)).array;

    auto limitRange = limitOrAllRange(fixedDb, inFiles.map!(a => cast(string) a).array)
        .reduceMissingFiles(fixedDb);

    if (!compile_db.empty && !limitRange.isMissingFilesEmpty) {
        foreach (a; limitRange.missingFiles) {
            logger.error("Unable to find any compiler flags for ", a);
        }
        return ExitStatusType.Errors;
    }

    foreach (pdata; limitRange.range) {
        if (analyzeFile(pdata.cmd.absoluteFile, pdata.flags.completeFlags,
                visitor, ctx) == ExitStatusType.Errors) {
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
