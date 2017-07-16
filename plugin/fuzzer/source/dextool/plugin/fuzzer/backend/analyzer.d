/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.backend.analyzer;

import logger = std.experimental.logger;

import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.data : CppRoot, CppClass, CppMethod, CppCtor, CppDtor,
    CFunction, CppNamespace, USRType, Language, LocationTag, Location;

import dextool.type : FileName;

import dextool.plugin.fuzzer.backend.interface_;

/// Data derived during analyze of one translation unit.
struct AnalyzeData {
    static auto make() {
        auto r = AnalyzeData(CppRoot.make);
        return r;
    }

    CppRoot root;
    alias root this;

    /// Either all functions have the same or it is a mix which result in unknown.
    Language languageOfTranslationUnit;

    FileName fileOfTranslationUnit;
}

private enum LanguageAnalyzeState {
    none,
    unknown,
    oneLanguage,
    mixed
}

private LanguageAnalyzeState mergeLanguage(LanguageAnalyzeState st,
        Language func_lang, ref Language current_lang) @safe pure nothrow @nogc {
    import std.algorithm : among;

    final switch (st) {
    case LanguageAnalyzeState.none:
        if (func_lang.among(Language.c, Language.cpp)) {
            st = LanguageAnalyzeState.oneLanguage;
        } else {
            st = LanguageAnalyzeState.unknown;
        }
        break;
    case LanguageAnalyzeState.unknown:
        break;
    case LanguageAnalyzeState.oneLanguage:
        if (func_lang != current_lang) {
            st = LanguageAnalyzeState.mixed;
        }
        break;
    case LanguageAnalyzeState.mixed:
        break;
    }

    final switch (st) {
    case LanguageAnalyzeState.none:
        break;
    case LanguageAnalyzeState.unknown:
        current_lang = Language.unknown;
        break;
    case LanguageAnalyzeState.oneLanguage:
        current_lang = func_lang;
        break;
    case LanguageAnalyzeState.mixed:
        current_lang = Language.unknown;
        break;
    }

    return st;
}

final class TUVisitor : Visitor {
    import std.typecons : scoped, NullableRef;

    import cpptooling.analyzer.clang.ast : UnexposedDecl, FunctionDecl,
        TranslationUnit, generateIndentIncrDecr, LinkageSpec;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl;
    import cpptooling.data : CxReturnType;
    import cpptooling.data.symbol : Container;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    NullableRef!Container container;
    AnalyzeData root;

    private LanguageAnalyzeState lang_analyze_st;

    this(NullableRef!Container container) {
        this.container = container;
        this.root = AnalyzeData.make;
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(LinkageSpec) v) {
        mixin(mixinNodeLog!());
        // extern "C"... etc
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, container, indent);
        if (!result.isValid) {
            return;
        }

        auto func = CFunction(result.type.kind.usr, result.name, result.params,
                CxReturnType(result.returnType), result.isVariadic, result.storageClass);
        func.language = result.language;
        root.put(func);

        mergeLanguage(lang_analyze_st, result.language, root.languageOfTranslationUnit);

        debug logger.tracef("FunctionDecl, language: %s tu(%s)",
                result.language, root.languageOfTranslationUnit);
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());

        root.fileOfTranslationUnit = FileName(v.cursor.spelling);

        v.accept(this);
    }
}
