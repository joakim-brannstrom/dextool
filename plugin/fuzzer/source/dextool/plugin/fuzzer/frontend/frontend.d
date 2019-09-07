/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.frontend.frontend;

import std.regex : Regex;
import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type;

import dextool.plugin.types;

import dextool.plugin.fuzzer.type;

import dextool.plugin.fuzzer.frontend.raw_args : RawConfiguration, XmlConfig, Symbols;
import dextool.plugin.fuzzer.backend.interface_ : Controller, Parameter, Product, Transform;

private struct FileData {
    import dextool.type : FileName, WriteStrategy;

    invariant {
        // cant have data in both.
        assert(str_data.length == 0 || raw_data.length == 0);
    }

    FileName filename;
    string str_data;
    const(void)[] raw_data;
    WriteStrategy strategy;

    const(void)[] data() {
        if (str_data.length != 0) {
            return cast(void[]) str_data;
        } else {
            return raw_data;
        }
    }
}

class FuzzerFrontend : Controller, Parameter, Product, Transform {
    import std.regex : regex, Regex;
    import std.typecons : Flag;
    import dextool.compilation_db : CompileCommandFilter;
    import dextool.type : FileName;
    import cpptooling.testdouble.header_filter : TestDoubleIncludes, LocationType;
    import dsrcgen.cpp : CppModule, CppHModule;

    private {
        static const hdrExt = ".hpp";
        static const implExt = ".cpp";
        static const xmlExt = ".xml";
        static const rawExt = ".bin";

        CustomHeader custom_hdr;

        /// Output directory to generate data in such as code.
        DirName output_dir;

        /// Used to match symbols by their location.
        Regex!char[] exclude;
        Regex!char[] restrict;

        /// Data produced by the generatore intented to be written to specified file.
        FileData[] file_data;

        CompileCommandFilter compiler_flag_filter;
        Symbols symbols;
    }

    static auto make(ref RawConfiguration args) {
        // dfmt off
        auto r = new FuzzerFrontend(DirName(args.out_))
            .argFileExclude(args.fileExclude)
            .argFileRestrict(args.fileRestrict)
            .argXmlConfig(args.xmlConfig);
        // dfmt on
        return r;
    }

    this(DirName output_dir) {
        this.output_dir = output_dir;
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

    /// Ensure that the relevant information from the xml file is extracted.
    auto argXmlConfig(Nullable!XmlConfig conf) {
        import dextool.compilation_db : defaultCompilerFlagFilter;

        if (conf.isNull) {
            compiler_flag_filter = CompileCommandFilter(defaultCompilerFlagFilter, 1);
            return this;
        }

        compiler_flag_filter = CompileCommandFilter(conf.get.filterClangFlags,
                conf.get.skipCompilerArgs);
        symbols = conf.get.symbols;

        return this;
    }

    ref CompileCommandFilter getCompileCommandFilter() {
        return compiler_flag_filter;
    }

    /// Data produced by the generatore intented to be written to specified file.
    ref FileData[] getProducedFiles() {
        return file_data;
    }

    ref Symbols getSymbols() {
        return symbols;
    }

    // -- Controller --

    @safe bool doSymbolAtLocation(const string filename, const string symbol) {
        import dextool.plugin.regex_matchers : matchAny;

        // if there are no filter registered then it automatically passes.

        bool restrict_pass = restrict.length == 0 || matchAny(filename, restrict);
        debug logger.tracef(!restrict_pass,
                "--file-restrict skipping: %s in %s", symbol, filename);

        bool exclude_pass = exclude.length == 0 || !matchAny(filename, exclude);
        debug logger.tracef(!exclude_pass, "--file-exclude skipping: %s in %s", symbol, filename);

        return restrict_pass && exclude_pass;
    }

    bool doSymbol(string symbol) {
        if (auto sym = symbols.lookup(FullyQualifiedNameType(symbol))) {
            if (sym.filter == Symbol.FilterKind.exclude) {
                return false;
            }
        }

        return true;
    }

    // -- Parameters --

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

    void putFile(FileName fname, CppModule impl_data,
            WriteStrategy strategy = WriteStrategy.overwrite) {
        file_data ~= FileData(fname, impl_data.render(), null, strategy);
    }

    void putFile(FileName fname, const(ubyte)[] raw_data) {
        file_data ~= FileData(fname, null, raw_data);
    }

    void putFile(FileName fname, string raw_data, WriteStrategy strategy = WriteStrategy.overwrite) {
        file_data ~= FileData(fname, null, raw_data, strategy);
    }

    // -- Transform --
    FileName createHeaderFile(string name) {
        import std.path : buildPath;

        return FileName(buildPath(output_dir, name ~ hdrExt));
    }

    FileName createImplFile(string name) {
        import std.path : buildPath;

        return FileName(buildPath(output_dir, name ~ implExt));
    }

    FileName createFuzzCase(string name, ulong id) {
        import std.conv : to;
        import std.path : buildPath;

        return FileName(buildPath(output_dir, name ~ id.to!string ~ implExt));
    }

    FileName createFuzzyDataFile(string name) {
        import std.path : buildPath;

        return FileName(buildPath(output_dir, "test_case", name ~ rawExt));
    }

    // try the darnest to not overwrite an existing config.
    FileName createXmlConfigFile(string name) {
        import std.conv : to;
        import std.path : buildPath;
        import std.file : exists;

        string p = buildPath(output_dir, name ~ xmlExt);

        for (int i = 0; exists(p); ++i) {
            p = buildPath(output_dir, name ~ i.to!string() ~ xmlExt);
        }

        return FileName(p);
    }
}

auto genFuzzer(FuzzerFrontend frontend, in string[] in_cflags,
        CompileCommandDB compile_db, InFiles in_files, Regex!char strip_incl) {
    import dextool.io : writeFileData;
    import dextool.plugin.fuzzer.backend.backend : Backend;
    import dextool.utility : prependDefaultFlags, PreferLang;

    const auto user_cflags = prependDefaultFlags(in_cflags, PreferLang.none);
    const auto total_files = in_files.length;
    auto backend = Backend(frontend, frontend, frontend, frontend, strip_incl);

    foreach (idx, in_file; in_files) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        string[] use_cflags;
        AbsolutePath analyze_file;

        if (compile_db.length > 0) {
            auto db_search_result = compile_db.appendOrError(user_cflags,
                    in_file, frontend.getCompileCommandFilter);
            if (db_search_result.isNull) {
                return ExitStatusType.Errors;
            }
            use_cflags = db_search_result.get.cflags;
            analyze_file = db_search_result.get.absoluteFile;
        } else {
            use_cflags = user_cflags.dup;
            analyze_file = AbsolutePath(FileName(in_file));
        }

        if (backend.analyzeFile(analyze_file, use_cflags) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }
    }

    backend.finalizeIncludes;

    // Analyse and generate interceptors
    backend.process(frontend.getSymbols, frontend.getCompileCommandFilter);

    return writeFileData(frontend.getProducedFiles);
}
