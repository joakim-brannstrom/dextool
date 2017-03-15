/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Generation of C++ test doubles.
*/
module plugin.frontend.cpptestdouble;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type;
import dextool.utility;

import plugin.types;
import plugin.backend.cpptestdouble.cppvariant : Controller, Parameters,
    Products;

struct RawConfiguration {
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
    bool shortPluginHelp;
    bool help;
    bool gmock;
    bool generatePreInclude;
    bool genPostInclude;

    string[] originalFlags;

    void parse(string[] args) {
        import std.getopt;

        originalFlags = args.dup;

        try {
            // dfmt off
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
                "gmock", &gmock,
                "gen-pre-incl", &generatePreInclude,
                "gen-post-incl", &genPostInclude,
                "td-include", &testDoubleInclude,
                "file-exclude", &fileExclude,
                "file-restrict", &fileRestrict,
                "in", &inFiles,
                "config", &config);
        // dfmt on
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
--gen-post-incl     :%s
--gen-pre-incl      :%s
--help              :%s
--td-include        :%s
--config            :%s
CFLAGS              :%s

xmlConfig           :%s", header, headerFile, fileRestrict, prefix, gmock,
                out_, fileExclude, mainName, stripInclude,
                mainFileName, inFiles, compileDb, genPostInclude, generatePreInclude,
                help, testDoubleInclude, config, cflags, xmlConfig);
    }
}

// dfmt off
static auto cpptestdouble_opt = CliOptionParts(
    "usage:
 dextool cpptestdouble [options] [--compile-db=...] [--file-exclude=...] [--td-include=...] --in=... [--] [CFLAGS...]
 dextool cpptestdouble [options] [--compile-db=...] [--file-restrict=...] [--td-include=...] --in=... [--] [CFLAGS...]",
    // -------------
    " --out=dir          directory for generated files [default: ./]
 --main=name        Used as part of interface, namespace etc [default: TestDouble]
 --main-fname=n     Used as part of filename for generated files [default: test_double]
 --prefix=p         Prefix used when generating test artifacts [default: Test_]
 --strip-incl=r     A regex used to strip the include paths
 --gmock            Generate a gmock implementation of test double interface
 --gen-pre-incl     Generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    Generate a post include header file if it doesn't exist and use it
 --header=s         Prepend generated files with the string
 --header-file=f    Prepend generated files with the header read from the file
 --config=path      Use configuration file",
    // -------------
"others:
 --in=              Input files to parse
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

struct FileData {
    import dextool.type : FileName;

    FileName filename;
    string data;
}

/** Test double generation of C++ code.
 *
 * TODO Describe the options.
 * TODO implement --in=...
 */
class CppTestDoubleVariant : Controller, Parameters, Products {
    import std.string : toLower;
    import std.regex : regex, Regex;
    import std.typecons : Flag;
    import dextool.compilation_db : CompileCommandFilter;
    import dextool.type : StubPrefix, FileName, MainInterface, DirName;
    import dextool.utility;
    import cpptooling.testdouble.header_filter : TestDoubleIncludes,
        LocationType;
    import dsrcgen.cpp;

    private {
        static const hdrExt = ".hpp";
        static const implExt = ".cpp";
        static const xmlExt = ".xml";

        StubPrefix prefix;

        DirName output_dir;
        FileName main_file_hdr;
        FileName main_file_impl;
        FileName main_file_globals;
        FileName gmock_file;
        FileName pre_incl_file;
        FileName post_incl_file;
        FileName config_file;
        FileName log_file;
        CustomHeader custom_hdr;

        MainName main_name;
        MainNs main_ns;
        MainInterface main_if;
        Flag!"Gmock" gmock;
        Flag!"PreInclude" pre_incl;
        Flag!"PostInclude" post_incl;

        Nullable!XmlConfig xmlConfig;
        CompileCommandFilter compiler_flag_filter;

        Regex!char[] exclude;
        Regex!char[] restrict;

        /// Data produced by the generatore intented to be written to specified file.
        FileData[] file_data;

        TestDoubleIncludes td_includes;
    }

    static auto makeVariant(ref RawConfiguration args) {
        // dfmt off
        auto variant = new CppTestDoubleVariant(MainFileName(args.mainFileName),
                DirName(args.out_),
                regex(args.stripInclude))
            .argPrefix(args.prefix)
            .argMainName(args.mainName)
            .argGmock(args.gmock)
            .argPreInclude(args.generatePreInclude)
            .argPostInclude(args.genPostInclude)
            .argForceTestDoubleIncludes(args.testDoubleInclude)
            .argFileExclude(args.fileExclude)
            .argFileRestrict(args.fileRestrict)
            .argCustomHeader(args.header, args.headerFile)
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
    this(MainFileName main_fname, DirName output_dir, Regex!char strip_incl) {
        this.output_dir = output_dir;
        this.td_includes = TestDoubleIncludes(strip_incl);

        import std.path : baseName, buildPath, stripExtension;

        string base_filename = cast(string) main_fname;

        this.main_file_hdr = FileName(buildPath(cast(string) output_dir, base_filename ~ hdrExt));
        this.main_file_impl = FileName(buildPath(cast(string) output_dir, base_filename ~ implExt));
        this.main_file_globals = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_global" ~ implExt));
        this.gmock_file = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_gmock" ~ hdrExt));
        this.pre_incl_file = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_pre_includes" ~ hdrExt));
        this.post_incl_file = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_post_includes" ~ hdrExt));
        this.config_file = FileName(buildPath(output_dir, base_filename ~ "_config" ~ xmlExt));
        this.log_file = FileName(buildPath(output_dir, base_filename ~ "_log" ~ xmlExt));
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

    /** Ensure that the relevant information from the xml file is extracted.
     *
     * May overwrite information from the command line.
     * TODO or should the command line have priority over the xml file?
     */
    auto argXmlConfig(Nullable!XmlConfig conf) {
        import dextool.compilation_db : defaultCompilerFlagFilter;

        if (conf.isNull) {
            compiler_flag_filter = CompileCommandFilter(defaultCompilerFlagFilter, 1);
            return this;
        }

        xmlConfig = conf;
        compiler_flag_filter = CompileCommandFilter(conf.filterClangFlags, conf.skipCompilerArgs);

        return this;
    }

    /// Destination of the configuration file containing how the test double was generated.
    FileName getXmlConfigFile() {
        return config_file;
    }

    /** Destination of the xml log for how dextool was ran when generatinng the
     * test double.
     */
    FileName getXmlLog() {
        return log_file;
    }

    ref CompileCommandFilter getCompileCommandFilter() {
        return compiler_flag_filter;
    }

    /// Data produced by the generatore intented to be written to specified file.
    ref FileData[] getProducedFiles() {
        return file_data;
    }

    void putFile(FileName fname, string data) {
        file_data ~= FileData(fname, data);
    }

    // -- Controller --

    bool doFile(in string filename, in string info) {
        import std.algorithm : canFind;
        import std.regex : matchFirst;

        bool r = true;

        // blocks during parsing so both restrict and exclude cannot be set at
        // the same time.
        if (restrict.length > 0) {
            r = canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(restrict);
            debug {
                logger.tracef(!r, "--file-restrict skipping %s", info);
            }
        } else if (exclude.length > 0) {
            r = !canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(exclude);
            debug {
                logger.tracef(!r, "--file-exclude skipping %s", info);
            }
        }

        return r;
    }

    bool doGoogleMock() {
        return gmock;
    }

    bool doPreIncludes() {
        import std.path : exists;

        return pre_incl && !exists(cast(string) pre_incl_file);
    }

    bool doIncludeOfPreIncludes() {
        return pre_incl;
    }

    bool doPostIncludes() {
        import std.path : exists;

        return post_incl && !exists(cast(string) post_incl_file);
    }

    bool doIncludeOfPostIncludes() {
        return post_incl;
    }

    void locationFilterDone() {
        td_includes.process();
        td_includes.finalize();
    }

    // -- Parameters --

    FileName[] getIncludes() {
        import std.algorithm : map;
        import std.array : array;

        return td_includes.includes.map!(a => FileName(a)).array();
    }

    DirName getOutputDirectory() {
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

    // -- Products --

    void putFile(FileName fname, CppHModule hdr_data) {
        file_data ~= FileData(fname, hdr_data.render());
    }

    void putFile(FileName fname, CppModule impl_data) {
        file_data ~= FileData(fname, impl_data.render());
    }

    void putLocation(FileName fname, LocationType type) {
        td_includes.put(fname, type);
    }
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
}

static import dextool.xml;

alias readRawConfig = dextool.xml.readRawConfig!(XmlConfig, parseRawConfig);

auto parseRawConfig(T)(T xml) @trusted {
    import std.conv : to, ConvException;
    import std.xml;

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

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlLog(AppT)(ref AppT app, string[] raw_cli_flags,) {
    import std.algorithm : joiner, copy;
    import std.array : array;
    import std.file : thisExePath;
    import std.format : format;
    import std.path : baseName;
    import std.utf : toUTF8;
    import std.xml;
    import dextool.utility : dextoolVersion;
    import dextool.xml : makePrelude;

    auto doc = new Document(new Tag("dextool"));
    doc.tag.attr["version"] = dextoolVersion;
    {
        auto command = new Element("command");
        command ~= new CData(format("%s %s", thisExePath.baseName,
                raw_cli_flags.joiner(" ").array().toUTF8));
        doc ~= new Comment("command line when dextool was executed");
        doc ~= command;
    }

    makePrelude(app);
    doc.pretty(4).joiner("\n").copy(app);

    return app;
}

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlConfig(AppT)(ref AppT app, CompileCommandFilter compiler_flag_filter) {
    import std.algorithm : joiner, copy;
    import std.conv : to;
    import std.xml;
    import dextool.utility : dextoolVersion;
    import dextool.xml : makePrelude;

    auto doc = new Document(new Tag("dextool"));
    doc.tag.attr["version"] = dextoolVersion;
    {
        auto compiler_tag = new Element("compiler_flag_filter");
        compiler_tag.tag.attr["skip_compiler_args"]
            = compiler_flag_filter.skipCompilerArgs.to!string();
        foreach (value; compiler_flag_filter.filter) {
            auto tag = new Element("exclude");
            tag ~= new Text(value);
            compiler_tag ~= tag;
        }
        doc ~= compiler_tag;
    }

    makePrelude(app);
    doc.pretty(4).joiner("\n").copy(app);

    return app;
}

/// TODO refactor, doing too many things.
ExitStatusType genCpp(CppTestDoubleVariant variant, string[] in_cflags,
        CompileCommandDB compile_db, InFiles in_files) {
    import std.conv : text;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : Yes;

    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.representation : CppRoot;
    import plugin.backend.cpptestdouble.cppvariant : Generator, CppVisitor;
    import dextool.io : writeFileData;

    auto visitor = new CppVisitor!(CppRoot, Controller, Products)(variant, variant);
    const auto user_cflags = prependDefaultFlags(in_cflags, "-xc++");
    auto in_file = cast(string) in_files[0];
    logger.trace("Input file: ", in_file);
    string[] use_cflags;
    string abs_in_file;

    if (compile_db.length > 0) {
        auto db_search_result = compile_db.appendOrError(user_cflags, in_file,
                variant.getCompileCommandFilter);
        if (db_search_result.isNull) {
            return ExitStatusType.Errors;
        }
        use_cflags = db_search_result.get.cflags;
        abs_in_file = db_search_result.get.absoluteFile;
    } else {
        use_cflags = user_cflags.dup;
        abs_in_file = buildNormalizedPath(in_file).asAbsolutePath.text;
    }

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
        return ExitStatusType.Errors;
    }

    // process and put the data in variant.
    Generator(variant, variant, variant).process(visitor.root, visitor.container);

    debug {
        logger.trace(visitor);
    }

    return writeFileData(variant.file_data);
}
