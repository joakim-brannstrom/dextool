/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.intercept.frontend.intercept;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type;
import dextool.utility;

import dextool.plugin.types;

import dextool.plugin.intercept.frontend.raw_args : RawConfiguration, Symbols,
    XmlConfig;

import dextool.plugin.intercept.backend.interface_ : Controller, Parameters,
    Products, FileData;

/** Test double generation of C code.
 *
 * TODO Describe the options.
 */
class InterceptFrontend : Controller, Parameters, Products {
    import std.regex : regex, Regex;
    import std.typecons : Flag;
    import dextool.compilation_db : CompileCommandFilter;
    import dextool.type : StubPrefix, FileName, DirName;
    import cpptooling.testdouble.header_filter : TestDoubleIncludes,
        LocationType;
    import dsrcgen.cpp : CppModule, CppHModule;
    import dsrcgen.sh : ShScriptModule;

    private {
        static const hdrExt = ".hpp";
        static const implExt = ".cpp";
        static const xmlExt = ".xml";
        static const shExt = ".sh";

        StubPrefix prefix;

        DirName output_dir;
        FileName main_file_hdr;
        FileName main_file_impl;
        FileName script_file;
        CustomHeader custom_hdr;

        /// Data produced by the generatore intented to be written to specified file.
        FileData[] file_data;

        TestDoubleIncludes td_includes;
        CompileCommandFilter compiler_flag_filter;
        Symbols symbols;
    }

    static auto makeVariant(ref RawConfiguration args) {
        // dfmt off
        auto variant = new InterceptFrontend(
                MainFileName(args.mainFileName), DirName(args.out_),
                regex(args.stripInclude))
            .argPrefix(args.prefix)
            .argForceTestDoubleIncludes(args.testDoubleInclude)
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
        this.script_file = FileName(buildPath(output_dir, base_filename ~ shExt));
    }

    auto argPrefix(string s) {
        this.prefix = StubPrefix(s);
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

        compiler_flag_filter = CompileCommandFilter(conf.filterClangFlags, conf.skipCompilerArgs);
        symbols = conf.symbols;

        return this;
    }

    void processIncludes() {
        td_includes.process();
    }

    void finalizeIncludes() {
        td_includes.finalize();
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

    /// If no symbols are specified to be intercept then all are intercepted.
    bool doSymbol(string symbol) {
        // fast path, assuming no symbol filter is the most common
        if (!symbols.hasSymbols) {
            return true;
        }

        return symbols.contains(symbol);
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
        return Parameters.Files(main_file_hdr, main_file_impl, script_file);
    }

    StubPrefix getFilePrefix() {
        return StubPrefix("");
    }

    DextoolVersion getToolVersion() {
        import dextool.utility : dextoolVersion;

        return dextoolVersion;
    }

    CustomHeader getCustomHeader() {
        return custom_hdr;
    }

    /// Defaults to the global if a specific prefix isn't provided.
    StubPrefix symbolPrefix(string symbol) {
        import dextool.plugin.intercept.frontend.raw_args : SymbolName;

        if (auto pref = SymbolName(symbol) in symbols.syms) {
            return StubPrefix((*pref).prefix);
        }

        return prefix;
    }

    // -- Products --

    void putFile(FileName fname, CppHModule hdr_data) {
        file_data ~= FileData(fname, hdr_data.render());
    }

    void putFile(FileName fname, CppModule impl_data) {
        file_data ~= FileData(fname, impl_data.render());
    }

    void putFile(FileName fname, ShScriptModule data) {
        file_data ~= FileData(fname, data.render());
    }

    void putLocation(FileName fname, LocationType type) {
        td_includes.put(fname, type);
    }
}

/// TODO refactor, doing too many things.
ExitStatusType genIntercept(InterceptFrontend frontend, in string[] in_cflags,
        CompileCommandDB compile_db, InFiles in_files) {
    import std.conv : text;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : Yes;

    import dextool.io : writeFileData;
    import dextool.plugin.intercept.backend.backend : Backend;

    const auto user_cflags = prependDefaultFlags(in_cflags, "");
    const auto total_files = in_files.length;
    auto backend = Backend(frontend, frontend, frontend);

    foreach (idx, in_file; in_files) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        string[] use_cflags;
        string abs_in_file;

        if (compile_db.length > 0) {
            auto db_search_result = compile_db.appendOrError(user_cflags,
                    in_file, frontend.getCompileCommandFilter);
            if (db_search_result.isNull) {
                return ExitStatusType.Errors;
            }
            use_cflags = db_search_result.get.cflags;
            abs_in_file = db_search_result.get.absoluteFile;
        } else {
            use_cflags = user_cflags.dup;
            abs_in_file = buildNormalizedPath(in_file).asAbsolutePath.text;
        }

        if (backend.analyzeFile(abs_in_file, use_cflags) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        frontend.processIncludes;
    }

    frontend.finalizeIncludes;

    // Analyse and generate interceptors
    backend.process();

    return writeFileData(frontend.getProducedFiles);
}
