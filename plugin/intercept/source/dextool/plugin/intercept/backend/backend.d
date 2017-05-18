/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.intercept.backend.backend;

import logger = std.experimental.logger;

import dextool.plugin.intercept.backend.analyzer;
import dextool.plugin.intercept.backend.interface_;
import dextool.type : StubPrefix;

struct Backend {
    import std.typecons : Nullable;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.symbol.container : Container;
    import dextool.type : ExitStatusType;

    ///
    this(Controller ctrl, Parameters params, Products products) {
        import std.typecons : Yes;

        this.analyze = AnalyzeData.make();
        this.ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
    }

    ExitStatusType analyzeFile(const string abs_in_file, const string[] use_cflags) {
        import std.typecons : NullableRef, scoped;
        import dextool.utility : analyzeFile;
        import cpptooling.data.representation : MergeMode;

        NullableRef!Container cont_ = &container;
        auto visitor = new TUVisitor(ctrl, products, cont_);

        if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        debug logger.tracef("%u", visitor.root);

        auto filtered = rawFilter(visitor.root, ctrl, products,
                (USRType usr) => container.find!LocationTag(usr));

        analyze.root.merge(filtered, MergeMode.full);

        return ExitStatusType.Ok;
    }

    void process() {
        import cpptooling.data.symbol.types : USRType;

        assert(!analyze.isNull);

        debug logger.trace(container.toString);

        logger.tracef("Filtered:\n%u", analyze.root);

        auto impl_data = ImplData.make();
        translate(analyze.root, container, ctrl, params, impl_data);
        analyze.nullify();

        logger.tracef("Translated to implementation:\n%u", impl_data.root);

        generate(impl_data, gen_data, params, container);

        postProcess(ctrl, params, products, gen_data);
    }

private:
    ClangContext ctx;
    Container container;
    Nullable!AnalyzeData analyze;
    GeneratedData gen_data;

    Controller ctrl;
    Parameters params;
    Products products;
}

private:

@safe:

import cpptooling.data.representation : CppRoot, CFunction, USRType;
import cpptooling.data.type : LocationTag, Location;
import cpptooling.data.symbol.container : Container;

import dsrcgen.cpp : CppModule, CppHModule;
import dsrcgen.sh : ShModule, ShScriptModule;

import dextool.plugin.intercept.type : SymbolName;

struct ImplData {
    import cpptooling.data.type : CppMethodName;

    CppRoot root;

    static auto make() {
        return ImplData(CppRoot.make);
    }

    StubPrefix[SymbolName] symbolPrefix;
}

/** Filter the raw IR according to the users desire.
 *
 * Params:
 *  ctrl = removes according to directives via ctrl
 *  prod = put locations of symbols that pass filtering
 */
AnalyzeData rawFilter(LookupT)(AnalyzeData input, Controller ctrl, Products prod, LookupT lookup) @safe {
    import std.algorithm : each, filter;
    import std.range : tee;
    import dextool.type : FileName;
    import cpptooling.data.representation : StorageClass;
    import cpptooling.generator.utility : filterAnyLocation;
    import cpptooling.testdouble.header_filter : LocationType;

    auto filtered = AnalyzeData.make;

    // dfmt off
    input.funcRange
        // by definition static functions can't be replaced by test doubles
        .filter!(a => a.storageClass != StorageClass.Static)
        // ask controller if the symbol should be intercepted
        .filter!(a => ctrl.doSymbol(a.name))
        // lookup the location of the symbol
        .filterAnyLocation!(a => true)(lookup)
        // pass on location as a product to be used to calculate #include
        .tee!(a => prod.putLocation(FileName(a.location.file), LocationType.Leaf))
        .each!(a => filtered.put(a.value));
    // dfmt on

    return filtered;
}

/** Structurally transform the input to an interceptor.
 *
 * It is intended to capture any transformations that are needed but atm it is
 * pretty useless.
 */
void translate(CppRoot root, ref Container container, Controller ctrl,
        Parameters params, ref ImplData impl) {
    foreach (f; root.funcRange) {
        impl.root.put(f);
        impl.symbolPrefix[SymbolName(f.name)] = params.symbolPrefix(cast(string) f.name);
    }
}

struct Code {
    enum Kind {
        hdr,
        impl,
        script
    }

    ShModule script;
    CppModule cpp;
}

struct GeneratedData {
    Code[Code.Kind] data;

    auto make(Code.Kind kind) {
        if (auto c = kind in data) {
            return *c;
        }

        Code m;

        final switch (kind) {
        case Code.Kind.hdr:
            goto case;
        case Code.Kind.impl:
            m.cpp = new CppModule;
            break;
        case Code.Kind.script:
            m.script = new ShModule;
            break;
        }

        data[kind] = m;
        return m;
    }
}

/** Translate the structure to code. */
void generate(ref ImplData impl, ref GeneratedData gen, Parameters params,
        ref const Container container) {
    import std.algorithm : filter;

    auto code_hdr = gen.make(Code.Kind.hdr).cpp;
    auto code_impl = gen.make(Code.Kind.impl).cpp;
    auto script = gen.make(Code.Kind.script).script;

    generateRewriteScriptPreamble(script);

    foreach (f; impl.root.funcRange) {
        StubPrefix prefix = impl.symbolPrefix[SymbolName(f.name)];

        generateInterceptFuncDecl(f, code_hdr, prefix);
        generateInterceptFunc(f, code_impl, prefix);
        generateRewriteSymbol(f, script, prefix);
    }
}

void generateInterceptFunc(CFunction f, CppModule code, StubPrefix prefix) {
    import cpptooling.data.representation : joinParams, joinParamNames;
    import cpptooling.analyzer.type : toStringDecl;
    import dsrcgen.c : E;

    // assuming that a function declaration void a() in C is meant to be void
    // a(void), not variadic.
    string params;
    auto p_range = f.paramRange();
    if (p_range.length == 1 && !f.isVariadic || p_range.length > 1) {
        params = joinParams(p_range);
    }
    string names = joinParamNames(f.paramRange());

    with (code.func_body(f.returnType.toStringDecl, f.name, params)) {
        auto expr = E(prefix ~ f.name)(E(names));
        if (f.returnType.toStringDecl == "void") {
            stmt(expr);
        } else {
            return_(expr);
        }
    }

    code.sep(2);
}

void generateInterceptFuncDecl(CFunction f, CppModule code, StubPrefix prefix) {
    import cpptooling.analyzer.type : toStringDecl;
    import cpptooling.data.representation : joinParams;
    import dsrcgen.c : E;

    // assuming that a function declaration void a() in C is meant to be void
    // a(void), not variadic.
    string params;
    auto p_range = f.paramRange();
    if (p_range.length == 1 && !f.isVariadic || p_range.length > 1) {
        params = joinParams(p_range);
    }

    code.func(f.returnType.toStringDecl, prefix ~ f.name, params);
    code.sep(2);
}

void generateRewriteSymbol(CFunction f, ShModule sh, StubPrefix prefix) {
    sh.stmt(`objcopy --redefine-sym ` ~ f.name ~ "=" ~ prefix ~ f.name ~ ` "$DEST"`);
}

void generateRewriteScriptPreamble(ShModule sh) {
    import std.ascii : newline;

    sh.stmt("set -e");

    with (sh.suite("if [ $# -ne 2 ]; then")[$.begin = newline, $.end = "fi"]) {
        stmt(`echo "Usage: $0 <original-lib> <rewrite-lib>"`);
        stmt("exit 1");
    }

    sh.stmt("ORIG=$1");
    sh.stmt("DEST=$2");

    sh.stmt(`hash objcopy || { echo "Missing objcopy"; exit 1; }`);
    sh.stmt(`cp "$ORIG" "$DEST"`);

    sh.sep(2);
}

void postProcess(Controller ctrl, Parameters params, Products prods, GeneratedData gen) {
    import cpptooling.generator.includes : convToIncludeGuard, makeHeader;
    import dextool.type : FileName, DextoolVersion, CustomHeader;

    static auto outputHdr(CppModule hdr, FileName fname, FileName[] includes,
            DextoolVersion ver, CustomHeader custom_hdr) {
        auto o = CppHModule(convToIncludeGuard(fname));
        o.header.append(makeHeader(fname, ver, custom_hdr));

        auto code_inc = o.content.suite(`extern "C" `);
        code_inc.suppressIndent(1);

        foreach (incl; includes) {
            code_inc.include(cast(string) incl);
        }
        code_inc.sep(2);

        code_inc.append(hdr);

        return o;
    }

    static auto output(CppModule code, FileName incl_fname, FileName dest,
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

    foreach (k, v; gen.data) {
        final switch (k) with (Code) {
        case Kind.hdr:
            prods.putFile(params.getFiles.hdr, outputHdr(v.cpp,
                    params.getFiles.hdr, params.getIncludes,
                    params.getToolVersion, params.getCustomHeader));
            break;
        case Kind.impl:
            prods.putFile(params.getFiles.impl, output(v.cpp,
                    params.getFiles.hdr, params.getFiles.impl,
                    params.getToolVersion, params.getCustomHeader));
            break;
        case Kind.script:
            auto script = ShScriptModule.make();
            script.shebang.shebang("/bin/bash");
            script.content.append(v.script);
            prods.putFile(params.getFiles.script, script);
            break;
        }
    }
}
