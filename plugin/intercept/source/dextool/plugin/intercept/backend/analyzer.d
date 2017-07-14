/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.intercept.backend.analyzer;

import logger = std.experimental.logger;

import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.data : CppRoot, CppClass, CppMethod, CppCtor, CppDtor,
    CFunction, CppNamespace, LocationTag, Location, USRType;

import dextool.plugin.intercept.backend.interface_;

/// Data derived during analyze.
struct AnalyzeData {
    static auto make() {
        auto r = AnalyzeData(CppRoot.make);
        return r;
    }

    CppRoot root;
    alias root this;
}

final class TUVisitor : Visitor {
    import std.typecons : scoped, NullableRef;

    import cpptooling.analyzer.clang.ast : UnexposedDecl, FunctionDecl,
        TranslationUnit, generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl;
    import cpptooling.data : CxReturnType;
    import cpptooling.data.symbol : Container;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    NullableRef!Container container;
    AnalyzeData root;

    this(NullableRef!Container container) {
        this.container = container;
        this.root = AnalyzeData.make;
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());

        // An unexposed may be:

        // an extern "C"
        // UnexposedDecl "" extern "C" {...
        //   FunctionDecl "fun_c_linkage" void func_c_linkage
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, container, indent);
        if (result.isValid) {
            auto func = CFunction(result.type.kind.usr, result.name, result.params,
                    CxReturnType(result.returnType), result.isVariadic, result.storageClass);
            root.put(func);
        }
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }
}
