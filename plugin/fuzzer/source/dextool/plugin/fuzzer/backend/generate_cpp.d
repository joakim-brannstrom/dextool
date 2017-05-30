/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains the C++ code generators.
*/
module dextool.plugin.fuzzer.backend.generate_cpp;

import logger = std.experimental.logger;

import cpptooling.data.type : CppNs, Language;
import cpptooling.data.representation : CppRoot, CFunction, USRType, CxParam,
    CppVariable;
import dsrcgen.cpp : CppModule, E, Et;

import dextool.plugin.fuzzer.type : Param, Symbol;
import dextool.plugin.fuzzer.backend.type;

@safe:

void generateMain(ref ImplData impl, CppModule m) {
    immutable dextool_hpp = "dextool/dextool.hpp";
    immutable afl_integration_hpp = "dextool/afl_integration.hpp";
    immutable guide_data = "guide_data";
    immutable default_src = "stdin_src";

    m.include(dextool_hpp);
    m.include(afl_integration_hpp);
    m.sep(2);

    with (m.namespace("dextool")) {
        suppressIndent(1);
        with (namespace("")) {
            suppressIndent(1);
            stmt(E("dextool::DefaultSource*") ~ E(default_src));
        }
        sep(2);

        with (func_body("DefaultSource&", "get_default_source")) {
            return_("*" ~ default_src);
        }
    }
    m.sep(2);

    with (m.func_body("int", "main", "int argc", "char** argv")) {
        return_(E("dextool::afl_main")("argc", "argv", "&dextool::" ~ default_src));
    }
}

private FuzzCase makeFuzzCase(IncludeT)(ulong index, IncludeT[] target_includes) {
    import std.conv : to;
    import dextool.type : FileName;

    auto r = FuzzCase(new CppModule);
    r.testCaseId = index;

    r.filename = FileName("dextool_fuzz_case");
    r.includes = r.cpp.base;
    r.includes.suppressIndent(1);

    r.includes.include("dextool/dextool.hpp");
    r.includes.sep(2);

    generateFuzzerTargetIncludes(target_includes, r.includes);
    r.includes.sep(2);

    r.body_ = r.cpp.suite(
            "FUZZ_TEST_S(Generated, Test" ~ index.to!string ~ ", " ~ index.to!string ~ ")");

    return r;
}

void generateFuzzCases(IncludeT)(ref ImplData impl, IncludeT[] target_includes, ref GeneratedData gen) {
    foreach (f; impl.root.funcRange) {
        auto test_case_id = impl.symbolId[FullyQualifiedNameType(f.name)];
        auto fc = makeFuzzCase(test_case_id, target_includes);
        generateFunctionFuzzTest(f, fc, impl.symbols);
        gen.fuzzCases ~= fc;
    }
}

private void generateFunctionFuzzTest(SymbolsT)(CFunction f, FuzzCase fc, SymbolsT symbols) {
    import std.typecons : No;
    import cpptooling.analyzer.type;
    import dextool.plugin.fuzzer.type : FullyQualifiedNameType, Param;

    if (auto sym = FullyQualifiedNameType(f.name) in symbols) {
        if (sym.hasFuzz) {
            generateFuncUserFuzzer(f, sym, fc.body_, fc.includes);
        } else if (sym.filter == Symbol.FilterKind.keep) {
            Param[] params = sym.limits;
            generateFuncParamFuzzer(f, params, fc.body_, fc.includes);
        }
    } else {
        generateFuncParamFuzzer(f, Param[].init, fc.body_, fc.includes);
    }
}

/// Generate the parameters with random values.
void generateFuncParamFuzzer(ParamsT)(CFunction f, ParamsT param_limits,
        CppModule f_, CppModule extra_includes) {
    import std.algorithm : joiner;
    import std.conv : to, text;
    import std.range : enumerate;
    import std.typecons : Yes, No;
    import cpptooling.data.representation : getName, unpackParam;
    import cpptooling.analyzer.type;

    struct Instantiate {
        string name;
        bool success;
    }

    Instantiate instantiateParamType(TypeT)(size_t idx, Param[] params,
            TypeT type, ref string[] param_id, CppModule m) {
        Instantiate rval;
        rval.name = "param" ~ idx.to!string;

        type.attr.isConst = No.isConst;
        type.attr.isPtr = No.isPtr;
        type.attr.isRef = No.isRef;
        type.attr.isFuncPtr = No.isFuncPtr;

        if (type.kind.info.kind == TypeKind.Info.Kind.pointer) {
            rval.success = false;
            param_id ~= rval.name;
            m.comment("Unable to fuzz a pointer. Use a custom fuzz function. Example:");
            m.comment(`<fuzz use="my_fuzz" include="my_include.hpp"/>`);
            m.stmt(E(type.toStringDecl(rval.name)) = E(0));
        } else {
            rval.success = true;
            param_id ~= rval.name;
            m.stmt(type.toStringDecl(rval.name));
        }

        return rval;
    }

    void injectUserFuzzer(Param p, string varname, CppModule m) {
        if (!p.hasFuzz) {
            m.stmt(E("dextool::fuzz")(varname));
            return;
        }

        if (p.fuzz.include.length != 0) {
            extra_includes.include(p.fuzz.include);
        }

        m.stmt(E(p.fuzz.use)(varname, p.fuzz.param));
    }

    void injectCheck(Param p, string varname, CppModule m) {
        if (!p.hasCheck)
            return;

        with (m.if_("!" ~ E(p.check)(p.condition, varname))) {
            return_;
        }
    }

    // generate the random values.
    with (f_) {
        string[] param_id;
        string[] params;

        foreach (pidx, p; f.paramRange.enumerate) {
            auto utype = p.unpackParam;
            if (utype.isVariadic)
                continue;
            auto type = utype.type;

            // create the local variable for the parameters
            auto ident = instantiateParamType(pidx, param_limits, type, param_id, f_);

            if (!ident.success)
                continue;

            if (pidx >= param_limits.length) {
                stmt(E("dextool::fuzz")(ident.name));
            } else {
                Param param = param_limits[pidx];
                injectUserFuzzer(param, ident.name, f_);
                injectCheck(param, ident.name, f_);
            }
        }

        stmt(E(f.name)(param_id.joiner(", ").text));
    }
}

void generateFuzzerTargetIncludes(IncludeT)(IncludeT[] includes, CppModule m) {
    foreach (incl; includes) {
        auto incl_code = m;
        if (incl.payload == Language.c) {
            incl_code = m.suite(`extern "C"`);
            incl_code.suppressIndent(1);
        }
        incl_code.include(cast(string) incl);
    }
    m.sep(2);
}

void generateFuncUserFuzzer(SymbolT)(CFunction f, SymbolT sym, CppModule f_,
        CppModule extra_includes) {
    import std.algorithm : map, joiner;
    import std.range : iota;
    import std.conv : to, text;

    if (sym.hasInclude) {
        extra_includes.include(sym.fuzz.include);
    }

    immutable user_ctx = "ctx";
    immutable prefix = "param";

    f_.stmt(E(sym.fuzz.use) ~ E(user_ctx));

    with (f_.if_("!" ~ user_ctx ~ ".is_valid")) {
        return_;
    }
    f_.sep(2);

    f_.stmt(E(f.name)(iota(f.paramRange.length)
            .map!(a => user_ctx ~ "." ~ prefix ~ a.text).joiner(", ").text));
}
