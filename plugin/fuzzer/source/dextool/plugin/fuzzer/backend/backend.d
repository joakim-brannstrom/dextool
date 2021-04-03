/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.backend.backend;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.plugin.fuzzer.backend.analyzer;
import dextool.plugin.fuzzer.backend.interface_;
import dextool.plugin.fuzzer.backend.type;

import dextool.compilation_db : CompileCommandFilter;
import dextool.type : Path, AbsolutePath;
import cpptooling.data.type : LocationTag, Location;

struct Backend {
    import libclang_ast.context : ClangContext;
    import cpptooling.data.symbol : Container;
    import cpptooling.testdouble.header_filter : GenericTestDoubleIncludes, LocationType;
    import dextool.type : ExitStatusType;
    import std.regex : Regex;

    this(Controller ctrl, Parameter params, Product products, Transform transf,
            Regex!char strip_incl) {
        import std.typecons : Yes;

        this.analyze = AnalyzeData.make();
        this.ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
        this.transf = transf;
        this.gen_code_includes = GenericTestDoubleIncludes!Language(strip_incl);
    }

    /// Frontend signals backend that all files have been processed.
    void finalizeIncludes() {
        gen_code_includes.finalize();
    }

    void putLocation(Path fname, LocationType type, Language lang) @safe {
        gen_code_includes.put(fname, type, lang);
    }

    ExitStatusType analyzeFile(const AbsolutePath analyze_file, const string[] use_cflags) {
        import std.typecons : NullableRef, scoped;
        import dextool.utility : analyzeFile;
        import cpptooling.data : MergeMode;

        NullableRef!Container cont_ = &container;
        auto visitor = new TUVisitor(cont_);

        if (analyzeFile(analyze_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        debug logger.tracef("%u", visitor.root);

        // dfmt off
        auto filtered = rawFilter(visitor.root, ctrl, products,
                (Path a, LocationType k, Language l) @safe => this.putLocation(a, k, l),
                (USRType usr) @safe => container.find!LocationTag(usr));
        // dfmt on

        analyze.get.root.merge(filtered, MergeMode.full);

        gen_code_includes.process();

        return ExitStatusType.Ok;
    }

    void process(SymbolsT)(ref SymbolsT syms, ref CompileCommandFilter compiler_flag_filter) {
        import std.algorithm : map;
        import std.array : array;

        assert(!analyze.isNull);

        debug {
            logger.trace(container.toString);
            logger.tracef("Filtered:\n%u", analyze.get.root);
        }

        auto impl_data = translate(analyze.get.root, syms, container);
        analyze.nullify();

        debug {
            logger.tracef("Translated to implementation:\n%u", impl_data.root);
            logger.tracef("Symbol data:\n%(%s:%s\n%)", impl_data.symbols);
        }

        generate(impl_data, compiler_flag_filter, gen_data,
                gen_code_includes.includesWithPayload.array(), container);

        postProcess(ctrl, transf, params, products, gen_data);
    }

private:
    ClangContext ctx;
    Container container;
    Nullable!AnalyzeData analyze;
    GeneratedData gen_data;

    Controller ctrl;
    Parameter params;
    Product products;
    Transform transf;

    GenericTestDoubleIncludes!Language gen_code_includes;
}

private:
@safe:

import cpptooling.data : CppRoot, CFunction, USRType, CxParam, CppVariable, CppNs, Language;
import cpptooling.data.symbol : Container;
import dextool.plugin.fuzzer.type : Param, Symbol;

import dsrcgen.cpp : CppModule, CppHModule;

/** Filter the raw IR according to the users desire.
 *
 * Params:
 *  ctrl = removes according to directives via ctrl
 *  prod = put locations of symbols that pass filtering
 */
AnalyzeData rawFilter(PutLocT, LookupT)(AnalyzeData input, Controller ctrl,
        Product prod, PutLocT putLoc, LookupT lookup) {
    import std.algorithm : each, filter;
    import std.range : tee;
    import dextool.type : Path;
    import cpptooling.data : StorageClass;
    import cpptooling.generator.utility : filterAnyLocation;
    import cpptooling.testdouble.header_filter : LocationType;

    if (ctrl.doSymbolAtLocation(input.fileOfTranslationUnit, input.fileOfTranslationUnit)) {
        putLoc(input.fileOfTranslationUnit, LocationType.Root, input.languageOfTranslationUnit);
    }

    auto filtered = AnalyzeData.make;

    // dfmt off
    input.funcRange
        // by definition static functions can't be replaced by test doubles
        .filter!(a => a.storageClass != StorageClass.Static)
        // ask controller if the symbol should be intercepted
        .filter!(a => ctrl.doSymbol(a.name))
        // ask controller if to generate wrapper for the function based on file location
        .filterAnyLocation!(a => ctrl.doSymbolAtLocation(a.location.file, a.value.name))(lookup)
        // pass on location as a product to be used to calculate #include
        .tee!(a => putLoc(Path(a.location.file), LocationType.Leaf, a.value.language.get))
        .each!(a => filtered.put(a.value));
    // dfmt on

    return filtered;
}

/** Structurally translate the input to a fuzz wrapper.
 *
 * Add/transform/remove constructs from the filtered data to make it suitable
 * to generate the fuzz wrapper.
 */
ImplData translate(SymbolsT)(CppRoot root, ref SymbolsT symbols, ref Container container) @trusted {
    import std.algorithm : map, filter;
    import dextool.plugin.fuzzer.backend.unique_sequence : Sequence;
    import dextool.plugin.fuzzer.type : Symbol, FullyQualifiedNameType, Param;

    Sequence!ulong test_case_seq_generator;
    auto impl = ImplData.make();

    void updateSeq(ref Symbol sym) {
        Symbol s = sym;
        test_case_seq_generator.putOrAdjust(s.sequenceId.payload);
        s.sequenceId.isValid = true;
        impl.symbols[sym.fullyQualifiedName] = s;
        impl.symbolId[sym.fullyQualifiedName] = s.sequenceId.payload;
    }

    // prepare the sequence number generator with all the used valid seq. nums.
    foreach (sym; symbols.byKeyValue
            .map!(a => a.value)
            .filter!(a => a.filter == Symbol.FilterKind.keep && a.sequenceId.isValid)) {
        updateSeq(sym);
    }

    // assign new, valid seq. nums for those symbols that had an invalid sequence.
    foreach (sym; symbols.byKeyValue
            .map!(a => a.value)
            .filter!(a => a.filter == Symbol.FilterKind.keep && !a.sequenceId.isValid)) {
        updateSeq(sym);
    }

    // prepare generation of the xml data from the excluded symbols.
    foreach (sym; symbols.byKeyValue
            .map!(a => a.value)
            .filter!(a => a.filter == Symbol.FilterKind.exclude)) {
        impl.excludedSymbols ~= IgnoreSymbol(sym.fullyQualifiedName);
    }

    // assign new numbers to those functions that are newly discovered.
    foreach (f; root.funcRange) {
        impl.root.put(f);

        if (FullyQualifiedNameType(f.name) in impl.symbolId) {
            // do nothing
        } else {
            ulong id;
            test_case_seq_generator.putOrAdjust(id);
            impl.symbolId[FullyQualifiedNameType(f.name)] = id;
        }
    }

    return impl;
}

/** Translate the structure to code.
 *
 * Keep it simple. Translate should have prepared the data to make this step
 * easy.
 * */
void generate(IncludeT)(ref ImplData impl, ref CompileCommandFilter compiler_flag_filter,
        ref GeneratedData gen, IncludeT[] target_includes, ref const Container container) {
    import dextool.plugin.fuzzer.backend.generate_cpp;
    import dextool.plugin.fuzzer.backend.generate_xml;

    // code
    gen.make(Code.Kind.configTemplate);
    generateMain(impl, gen.make(Code.Kind.main).cpp);
    generateFuzzCases(impl, target_includes, gen);

    // config
    generateConfigPerFunction(impl, gen.templateConfig);
    generateConfigCompilerFilter(compiler_flag_filter, gen.templateConfig);

    // fuzz binary data
    generateFuzzyInput(impl, gen);
}

/// Generate a initial data file for the fuzzer based on static analysis.
void generateFuzzyInput(ref ImplData impl, ref GeneratedData gen) {
    import std.range : repeat;
    import std.array : array, appender;
    import cpptooling.data : unpackParam;

    auto d = gen.make(Code.Kind.fuzzy);

    auto app = appender!(ubyte[])();

    foreach (f; impl.root.funcRange) {
        auto plen = f.paramRange.length;
        if (f.paramRange.length == 1 && f.paramRange[0].unpackParam.isVariadic) {
            plen -= 1;
        }

        // assume that each parameter is at least 4 bytes of fuzzy data
        app.put(repeat(ubyte(0), 4 * plen).array());
    }

    // must not be zero or AFL do not consider it as input
    if (app.data.length == 0) {
        app.put(ubyte(0));
    }

    d.fuzzyData = app.data;
    gen.data[Code.Kind.fuzzy] = d;
}

void postProcess(Controller ctrl, Transform transf, Parameter params,
        Product prods, ref GeneratedData gen) {
    import std.array : appender;
    import cpptooling.generator.includes : convToIncludeGuard, makeHeader;
    import cpptooling.type : CustomHeader;
    import dextool.io : WriteStrategy;
    import dextool.type : Path, DextoolVersion;

    static auto outputHdr(CppModule hdr, Path fname, DextoolVersion ver, CustomHeader custom_hdr) {
        auto o = CppHModule(convToIncludeGuard(fname));
        o.header.append(makeHeader(fname, ver, custom_hdr));
        o.content.append(hdr);

        return o;
    }

    static auto output(CppModule code, Path incl_fname, Path dest,
            DextoolVersion ver, CustomHeader custom_hdr) {
        import std.path : baseName;

        auto o = new CppModule;
        o.suppressIndent(1);
        o.append(makeHeader(dest, ver, custom_hdr));

        o.include(incl_fname.baseName);
        o.sep(2);

        o.append(code);

        return o;
    }

    static auto outputCase(CppModule code, Path dest, DextoolVersion ver, CustomHeader custom_hdr) {
        import std.path : baseName;

        auto o = new CppModule;
        o.suppressIndent(1);
        o.append(makeHeader(dest, ver, custom_hdr));
        o.append(code);

        return o;
    }

    static auto outputMain(CppModule code, Path dest, DextoolVersion ver, CustomHeader custom_hdr) {
        import std.path : baseName;

        auto o = new CppModule;
        o.suppressIndent(1);
        o.append(makeHeader(dest, ver, custom_hdr));
        o.append(code);

        return o;
    }

    immutable file_main = "main";
    immutable file_fuzzy_data = "dextool_rawdata";
    immutable file_config_tmpl = "dextool_config";

    foreach (k, v; gen.data) {
        final switch (k) with (Code) {
        case Kind.main:
            auto fname = transf.createImplFile(file_main);
            prods.putFile(fname, outputMain(v.cpp, fname,
                    params.getToolVersion, params.getCustomHeader));
            break;
        case Kind.fuzzy:
            auto fname = transf.createFuzzyDataFile(file_fuzzy_data);
            prods.putFile(fname, v.fuzzyData);
            break;
        case Kind.configTemplate:
            auto fname = transf.createXmlConfigFile(file_config_tmpl);
            auto app = appender!string();
            gen.templateConfig.put(app);
            prods.putFile(fname, app.data, WriteStrategy.skip);
            break;
        }
    }

    foreach (fc; gen.fuzzCases) {
        auto fname = transf.createFuzzCase(fc.filename, fc.testCaseId);
        prods.putFile(fname, outputCase(fc.cpp, fname, params.getToolVersion,
                params.getCustomHeader), WriteStrategy.skip);
    }
}
