/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.backend.generate_xml;

import std.conv : to;

import logger = std.experimental.logger;

import cpptooling.data.representation : CppRoot, CFunction, USRType, CxParam,
    CppVariable;

import dextool.compilation_db : CompileCommandFilter;

import dextool.plugin.fuzzer.type : Param, Symbol;
import dextool.plugin.fuzzer.backend.type;
import dextool.plugin.fuzzer.backend.unique_sequence : Sequence;

/// TODO change to @safe when the base compiler is upgraded to 2.074+
void generateConfigCompilerFilter(ref CompileCommandFilter compiler_flag_filter,
        ref TemplateConfig tmpl_conf) @trusted {
    import std.conv : to;
    import std.xml;

    auto compiler_tag = new Element("compiler_flag_filter");
    compiler_tag.tag.attr["skip_compiler_args"] = compiler_flag_filter
        .skipCompilerArgs.to!string();
    foreach (value; compiler_flag_filter.filter) {
        auto tag = new Element("exclude");
        tag ~= new Text(value);
        compiler_tag ~= tag;
    }

    tmpl_conf.doc ~= compiler_tag;
}

/// TODO change to @safe when the base compiler is upgraded to 2.074+
void generateConfigPerFunction(ref ImplData impl, ref TemplateConfig tmpl_conf) @trusted {
    import std.xml;
    import cpptooling.data.type : FullyQualifiedNameType;

    // no duplications are allowed
    bool[FullyQualifiedNameType] generated_syms;

    // dump the user excluded symbols
    foreach (s; impl.excludedSymbols) {
        auto sym = tmpl_conf.makeSymbol;
        sym.tag.attr["name"] = cast(FullyQualifiedNameType) s;
        sym.tag.attr["filter"] = "exclude";
        generated_syms[s] = true;
    }

    foreach (f; impl.root.funcRange) {
        if (auto s = FullyQualifiedNameType(f.name) in generated_syms) {
            continue;
        }

        auto sym = tmpl_conf.makeSymbol;

        if (auto s = FullyQualifiedNameType(f.name) in impl.symbols) {
            generateConfigForFunctionValidityFromUser(f, *s, sym);
        } else {
            generateConfigDefaultFunctionValidity(f,
                    impl.symbolId[FullyQualifiedNameType(f.name)], sym);
        }
    }
}

void generateConfigForFunctionValidityFromUser(T)(CFunction f, Symbol symbol, ref T sym) {
    import std.algorithm : map;
    import std.array : array;
    import std.conv : to;
    import std.range : enumerate;
    import std.xml;
    import cpptooling.data.representation : getName;

    // assuming that the fully qualified name is always valid xml
    sym.tag.attr["name"] = symbol.fullyQualifiedName;
    sym.tag.attr["id"] = symbol.sequenceId.to!string;

    string[] param_ids = f.paramRange.enumerate.map!(
            a => a.value.getName("param" ~ a.index.to!string)).array();

    if (symbol.hasFuzz) {
        auto fuzz = new Element("fuzz");
        sym ~= fuzz;
        fuzz.tag.attr["use"] = symbol.fuzz.use;
        fuzz.tag.attr["include"] = symbol.fuzz.include;
    }

    foreach (idx, p; symbol.limits.enumerate) {
        //TODO this sanity check should be at the translation stage. Not the code generation.
        if (idx >= param_ids.length) {
            logger.warningf("symbol '%s', too many parameter checkers. Discarding '%s'",
                    symbol.fullyQualifiedName, p.identifier);
            continue;
        } else if (param_ids[idx] != p.identifier) {
            logger.infof("symbol '%s', parameter identifier '%s' do not match the functions parameter '%s'",
                    f.name, p.identifier, param_ids[idx]);
        }

        auto xparam = new Element("param");
        sym ~= xparam;

        xparam.tag.attr["name"] = p.identifier;

        if (p.hasCheck) {
            auto valid = new Element("valid");
            xparam ~= valid;
            valid.tag.attr["check"] = p.check;
            valid.tag.attr["condition"] = p.condition;
        }

        if (p.hasFuzz) {
            auto fuzz = new Element("fuzz");
            xparam ~= fuzz;
            fuzz.tag.attr["use"] = p.fuzz.use;
            fuzz.tag.attr["param"] = p.fuzz.param;
            fuzz.tag.attr["include"] = p.fuzz.include;
        }
    }
}

void generateConfigDefaultFunctionValidity(T)(CFunction f, ulong seq_id, ref T sym) {
    import std.conv : to;
    import std.range : enumerate;
    import std.xml;
    import cpptooling.data.representation : getName;

    // assuming that the fully qualified name is always valid xml
    sym.tag.attr["name"] = f.name;
    sym.tag.attr["id"] = seq_id.to!string;

    foreach (idx, p; f.paramRange.enumerate) {
        auto xparam = new Element("param");
        sym ~= xparam;

        xparam.tag.attr["name"] = p.getName("param" ~ idx.to!string);

        auto valid = new Element("valid");
        xparam ~= valid;
        valid.tag.attr["check"] = "";
        valid.tag.attr["condition"] = "";

        auto fuzz = new Element("fuzz");
        xparam ~= fuzz;
        fuzz.tag.attr["use"] = "";
        fuzz.tag.attr["param"] = "";
        fuzz.tag.attr["include"] = "";
    }
}
