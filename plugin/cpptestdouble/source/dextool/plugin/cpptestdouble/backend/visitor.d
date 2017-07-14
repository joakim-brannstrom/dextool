/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.cpptestdouble.backend.visitor;

import logger = std.experimental.logger;

import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.data : CppRoot, CppClass, CppMethod, CppCtor, CppDtor,
    CFunction, CppNamespace, LocationTag, Location;
import cpptooling.data.symbol : USRType;

import dextool.plugin.cpptestdouble.backend.interface_;

/// Data derived during analyze
struct AnalyzeData {
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    static auto make() {
        AnalyzeData r;
        r.root = CppRoot.make;
        return r;
    }

    CppRoot root;

    /// Classes found during src analysis.
    CppClass[FullyQualifiedNameType] classes;

    void putForLookup(CppClass c) {
        classes[c.fullyQualifiedName] = c;
    }
}

private enum VisitorKind {
    root,
    child
}

alias CppTUVisitor = CppVisitor!(VisitorKind.root);

final class CppVisitor(VisitorKind RootT) : Visitor {
    import std.typecons : scoped, NullableRef;

    import cpptooling.analyzer.clang.ast : UnexposedDecl, VarDecl, FunctionDecl,
        ClassDecl, Namespace, TranslationUnit, generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl;
    import cpptooling.data : CppRoot, CxGlobalVariable, CppNsStack,
        CxReturnType, CppNs, TypeKindVariable;
    import cpptooling.data.symbol : Container;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    NullableRef!Container container;
    NullableRef!AnalyzeData analyze_data;

    private {
        Controller ctrl;
        Products prod;
        CppNsStack ns_stack;
    }

    static if (RootT == VisitorKind.root) {
        CppRoot root;

        this(Controller ctrl, Products prod, NullableRef!AnalyzeData analyze,
                NullableRef!Container container) {
            this.ctrl = ctrl;
            this.prod = prod;
            this.analyze_data = analyze;
            this.container = container;
            this.root = CppRoot.make;
        }
    } else {
        CppNamespace root;

        this(Controller ctrl, Products prod, uint indent, CppNsStack ns_stack,
                NullableRef!AnalyzeData analyze, NullableRef!Container container) {
            this.root = CppNamespace(ns_stack);
            this.ctrl = ctrl;
            this.prod = prod;
            this.indent = indent;
            this.ns_stack = ns_stack;
            this.analyze_data = analyze;
            this.container = container;
        }
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());

        // An unexposed may be:

        // an extern "C"
        // UnexposedDecl "" extern "C" {...
        //   FunctionDecl "fun_c_linkage" void func_c_linkage
        v.accept(this);
    }

    override void visit(const(VarDecl) v) @trusted {
        import deimos.clang.index : CX_StorageClass;

        mixin(mixinNodeLog!());

        // TODO investigate if linkage() == CXLinkage_External should be used
        // instead.
        if (v.cursor.storageClass() == CX_StorageClass.CX_SC_Extern) {
            auto result = analyzeVarDecl(v, container, indent);
            auto var = CxGlobalVariable(result.instanceUSR,
                    TypeKindVariable(result.type, result.name));
            root.put(var);
        }
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

    override void visit(const(ClassDecl) v) @trusted {
        import std.typecons : scoped;
        import cpptooling.analyzer.clang.analyze_helper : ClassVisitor;
        import cpptooling.analyzer.clang.type : retrieveType;
        import cpptooling.analyzer.clang.store : put;

        ///TODO add information if it is a public/protected/private class.
        ///TODO add metadata to the class if it is a definition or declaration

        mixin(mixinNodeLog!());
        logger.trace("class: ", v.cursor.spelling);

        if (v.cursor.isDefinition) {
            auto visitor = scoped!ClassVisitor(v, ns_stack, container, indent + 1);
            v.accept(visitor);

            root.put(visitor.root);
            analyze_data.putForLookup(visitor.root);
        } else {
            auto type = retrieveType(v.cursor, container, indent);
            put(type, container, indent);
        }
    }

    override void visit(const(Namespace) v) @trusted {
        mixin(mixinNodeLog!());

        () @trusted{ ns_stack ~= CppNs(v.cursor.spelling); }();
        // pop the stack when done
        scope (exit)
            ns_stack = ns_stack[0 .. $ - 1];

        auto ns_visitor = scoped!(CppVisitor!(VisitorKind.child))(ctrl, prod,
                indent, ns_stack, analyze_data, container);

        v.accept(ns_visitor);

        // fill the namespace with content from the analysis
        root.put(ns_visitor.root);
    }

    override void visit(const(TranslationUnit) v) {
        import std.algorithm : filter;
        import cpptooling.analyzer.clang.type : makeLocation;
        import cpptooling.testdouble.header_filter : LocationType;
        import dextool.type : FileName;

        mixin(mixinNodeLog!());

        LocationTag tu_loc;
        () @trusted{ tu_loc = LocationTag(Location(v.cursor.spelling, 0, 0)); }();

        if (tu_loc.kind != LocationTag.Kind.noloc && ctrl.doFile(tu_loc.file,
                "root " ~ tu_loc.toString)) {
            prod.putLocation(FileName(tu_loc.file), LocationType.Root);
        }

        v.accept(this);
    }
}
