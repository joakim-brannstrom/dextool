/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module test.component.analyzer.utility;

import std.algorithm : among;
import std.format : format;
import std.stdio : writeln;
import std.typecons : Yes, No;
import logger = std.experimental.logger;

import unit_threaded;
import test.clang_util;
import test.helpers;

// TODO this is a mega import. Reduce it.
import cpptooling.data;

import cpptooling.analyzer.clang.ast;
import cpptooling.analyzer.clang.analyze_helper;
import cpptooling.analyzer.clang.context : ClangContext;
import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
import cpptooling.analyzer.clang.type;
import cpptooling.data.symbol : Container;
import cpptooling.data : TypeKindVariable, VariadicType, Location, USRType,
    toStringDecl;
import cpptooling.utility.virtualfilesystem : FileName, Content;

final class TestVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    USRType[] globalsFound;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.cursor_backtrack;

        if (!v.usr.among("c:issue.hpp@T@TypeDef") && v.isGlobalOrNamespaceScope) {
            globalsFound ~= USRType(v.usr);
        }

        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.cursor_backtrack;

        if (!v.usr.among("c:issue.hpp@T@TypeDef") && v.isGlobalOrNamespaceScope) {
            globalsFound ~= USRType(v.usr);
        }

        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.cursor_backtrack;

        if (!v.usr.among("c:issue.hpp@T@TypeDef") && v.isGlobalOrNamespaceScope) {
            globalsFound ~= USRType(v.usr);
        }

        v.accept(this);
    }
}

@("Should ignore local variables")
// dfmt off
@Values("int",
        "signed int",
        "unsigned int",
        "unsigned",
        "char",
        "signed char",
        "unsigned char",
        "short",
        "signed short",
        "unsigned short",
        "long",
        "signed long",
        "unsigned long",
        "long long",
        "signed long long",
        "unsigned long long",
        "float",
        "double",
        "long double",
        "wchar_t",
        "bool",
        )
@Values(["",""], ["*", ""], ["&", " = d0"], ["*&", " = d1"])
@Tags("slow") // serial runtime is 1 sec, 219 ms
// dfmt on
unittest {
    immutable raw_code = "
    #define Type %s
    #define Mod %s
    #define Assign %s
    typedef Type TypeDef;

    Type Mod fun() {
        Type d0; Type* d1;
        Type Mod t Assign;
        return t;
    }

    TypeDef Mod gun() {
        Type d0; Type* d1;
        TypeDef Mod td Assign;
        return td;
    }

    class Class {
        Class() {
            Type d0; Type* d1;
            Type Mod t Assign;
            TypeDef Mod td Assign;
        }

        ~Class() {
            Type d0; Type* d1;
            Type Mod t Assign;
            TypeDef Mod td Assign;
        }

        Type Mod fun() {
            Type d0; Type* d1;
            Type Mod t Assign;
            return t;
        }

        TypeDef Mod gun() {
            Type d0; Type* d1;
            TypeDef Mod td Assign;
            return td;
        }
    };

    struct Struct {
        Type Mod fun() {
            Type d0; Type* d1;
            Type Mod t Assign;
            return t;
        }

        TypeDef Mod gun() {
            Type d0; Type* d1;
            TypeDef Mod td Assign;
            return td;
        }
    };
";

    // arrange
    auto visitor = new TestVisitor;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto code = format(raw_code, getValue!string, getValue!(string[], 1)[0],
            getValue!(string[], 1)[1]);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    writeln(visitor.globalsFound);
    visitor.globalsFound.length.shouldEqual(0);
}
