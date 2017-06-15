/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains the frontend for generating a C++ test double.

Responsible for:
 - Receiving the call from the main to start working.
 - User interaction.
    - Error reporting in a way that the user understand the error.
    - Writing files to the filesystem.
    - Parsing arguments and other interaction information from the user.
    - Configuration file handling.
 - Provide user data to the backend via the interface the backend own.
*/
module dextool.plugin.cpptestdouble.frontend.cpptestdouble;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type;

import dextool.plugin.types;
import dextool.plugin.cpptestdouble.backend.interface_ : Controller, Parameters,
    Products;
import dextool.plugin.cpptestdouble.frontend.raw_args : RawConfiguration,
    XmlConfig;

struct FileData {
    import dextool.type : FileName, WriteStrategy;

    FileName filename;
    string data;
    WriteStrategy strategy;
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
        Flag!"FreeFunction" do_free_funcs;
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
            .argGenFreeFunction(args.doFreeFuncs)
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

    auto argGenFreeFunction(bool a) {
        this.do_free_funcs = cast(Flag!"FreeFunction") a;
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

    /// Signal that a file has finished analyzing.
    void processIncludes() {
        td_includes.process();
    }

    /// Signal that all files have been analyzed.
    void finalizeIncludes() {
        td_includes.finalize();
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

    bool doFreeFunction() {
        return do_free_funcs;
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

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlLog(AppT)(ref AppT app, string[] raw_cli_flags,) {
    import std.algorithm : joiner, copy;
    import std.array : array;
    import std.file : thisExePath;
    import std.format : format;
    import std.path : baseName;
    import std.utf : byChar;
    import std.xml;
    import dextool.utility : dextoolVersion;
    import dextool.xml : makePrelude;

    auto doc = new Document(new Tag("dextool"));
    doc.tag.attr["version"] = dextoolVersion;
    {
        auto command = new Element("command");
        command ~= new CData(format("%s %s", thisExePath.baseName,
                raw_cli_flags.joiner(" ").byChar.array().idup));
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
    import std.typecons : Yes;

    import dextool.clang : findFlags, ParseData = SearchResult;
    import dextool.plugin.cpptestdouble.backend.cppvariant : Generator;
    import dextool.io : writeFileData;
    import dextool.type : AbsolutePath;
    import dextool.utility : prependDefaultFlags, PreferLang;

    const auto user_cflags = prependDefaultFlags(in_cflags, PreferLang.cpp);
    const auto total_files = in_files.length;
    auto generator = Generator(variant, variant, variant);

    foreach (idx, in_file; in_files) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        ParseData pdata;

        if (compile_db.length > 0) {
            auto tmp = compile_db.findFlags(FileName(in_file), user_cflags,
                    variant.getCompileCommandFilter);
            if (tmp.isNull) {
                return ExitStatusType.Errors;
            }
            pdata = tmp.get;
        } else {
            pdata.flags = user_cflags.dup;
            pdata.absoluteFile = AbsolutePath(FileName(in_file));
        }

        if (generator.analyzeFile(pdata.absoluteFile, pdata.flags) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        variant.processIncludes;
    }

    variant.finalizeIncludes;

    // All files analyzed, process and generate artifacts.
    generator.process();

    return writeFileData(variant.file_data);
}
