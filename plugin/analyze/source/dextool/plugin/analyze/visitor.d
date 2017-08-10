/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.analyze.visitor;

import cpptooling.analyzer.clang.ast : Visitor;
import dextool.type : FileName, AbsolutePath;

/** Calculate McCabe per file and function.
*/
final class TUVisitor : Visitor {
    import std.string : startsWith;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.data.symbol : Container;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.cpp;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    alias CallbackT(T) = void delegate(const(T) v) @safe;

    alias OnFunctionT = CallbackT!FunctionDecl;
    OnFunctionT onFunction;
    alias OnConstructorT = CallbackT!Constructor;
    OnConstructorT onConstructor;
    alias OnDestructorT = CallbackT!Destructor;
    OnDestructorT onDestructor;
    alias OnCXXMethod = CallbackT!CXXMethod;
    OnCXXMethod onCXXMethod;
    alias OnConversionFunction = CallbackT!ConversionFunction;
    OnConversionFunction onConversionFunction;
    alias OnFunctionTemplateT = CallbackT!FunctionTemplate;
    OnFunctionTemplateT onFunctionTemplate;
    alias OnClassTemplateT = CallbackT!ClassTemplate;
    OnClassTemplateT onClassTemplate;

    private AbsolutePath restrict;

    /**
     * Params:
     *  restrict = only analyze files starting with this path
     */
    this(AbsolutePath restrict) {
        this.restrict = restrict;
    }

    override void visit(const(TranslationUnit) v) {
        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        if (!v.cursor.location.path.startsWith(restrict))
            return;
        mixin(mixinNodeLog!());
        if (onFunction !is null)
            onFunction(v);

        v.accept(this);
    }

    override void visit(const(Constructor) v) {
        if (!v.cursor.location.path.startsWith(restrict))
            return;
        mixin(mixinNodeLog!());
        if (onConstructor !is null)
            onConstructor(v);

        v.accept(this);
    }

    override void visit(const(Destructor) v) {
        if (!v.cursor.location.path.startsWith(restrict))
            return;
        mixin(mixinNodeLog!());
        if (onDestructor !is null)
            onDestructor(v);

        v.accept(this);
    }

    override void visit(const(CXXMethod) v) {
        if (!v.cursor.location.path.startsWith(restrict))
            return;
        mixin(mixinNodeLog!());
        if (onCXXMethod !is null)
            onCXXMethod(v);

        v.accept(this);
    }

    override void visit(const(ConversionFunction) v) {
        if (!v.cursor.location.path.startsWith(restrict))
            return;
        mixin(mixinNodeLog!());
        if (onConversionFunction !is null)
            onConversionFunction(v);

        v.accept(this);
    }

    override void visit(const(FunctionTemplate) v) {
        if (!v.cursor.location.path.startsWith(restrict))
            return;
        mixin(mixinNodeLog!());
        if (onFunctionTemplate !is null)
            onFunctionTemplate(v);

        v.accept(this);
    }

    override void visit(const(ClassTemplate) v) {
        if (!v.cursor.location.path.startsWith(restrict))
            return;
        if (onClassTemplate !is null)
            onClassTemplate(v);

        v.accept(this);
    }

    override void visit(const(Directive) v) {
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        v.accept(this);
    }

    override void visit(const(Preprocessor) v) {
        v.accept(this);
    }

    override void visit(const(Reference) v) {
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        v.accept(this);
    }
}
