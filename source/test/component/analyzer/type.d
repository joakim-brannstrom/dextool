/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Precise testing of the Type analyzer of the Clang AST.
*/
module test.component.analyzer.type;

import std.format : format;
import std.typecons : scoped;
import std.variant : visit;

import unit_threaded;
import test.clang_util;

import cpptooling.analyzer.kind;
import cpptooling.analyzer.type : USRType, toStringDecl;
import cpptooling.analyzer.clang.ast;
import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr, Visitor;
import cpptooling.analyzer.clang.analyze_helper;
import cpptooling.analyzer.clang.context : ClangContext;
import cpptooling.analyzer.clang.type;
import cpptooling.data.symbol.container : Container;
import cpptooling.data.type : TypeKindVariable, VariadicType;
import cpptooling.utility.clang : logNode, mixinNodeLog;

final class FindFunctionDeclVisitor : Visitor {
    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    /// The USR to find.
    USRType find;

    FunctionDeclResult* result;
    bool found;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        if (this.find.length == 0 || v.cursor.usr == this.find) {
            result = new FunctionDeclResult(analyzeFunctionDecl(v, container, indent));
            found = true;
        }
    }
}

@Name("Should be a type of kind 'func'")
unittest {
    enum code = `
#include <clocale>

namespace dextool__gnu_cxx {
  extern "C" __typeof(uselocale) __uselocale;
}
`;

    // arrange
    auto visitor = new FindFunctionDeclVisitor;
    auto ctx = ClangContext.fromString!"issue.hpp"(code);
    visitor.find = "c:@F@__uselocale";

    // act
    auto ast = ClangAST!(typeof(visitor))(ctx.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(ctx).shouldBeFalse;
    visitor.found.shouldBeTrue;
    visitor.result.type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.func);
    (cast(string) visitor.result.name).shouldEqual("__uselocale");
}

@Name("Should be parameters and return type that are of primitive type")
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
@Tags("slow") // execution time is >500ms
// dfmt on
unittest {
    enum code = "%s fun(%s);";

    // arrange
    auto visitor = new FindFunctionDeclVisitor;
    auto ctx = ClangContext.fromString!"issue.hpp"(format(code,
            getValue!string, getValue!string));

    // act
    auto ast = ClangAST!(typeof(visitor))(ctx.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(ctx).shouldBeFalse;
    visitor.found.shouldBeTrue;
    visitor.result.type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.func);
    (cast(string) visitor.result.name).shouldEqual("fun");

    foreach (param; visitor.result.params) {
        TypeKindAttr type;
        // dfmt off
        param.visit!(
                     (TypeKindVariable v) => type = v.type,
                     (TypeKindAttr v) => type = v,
                     (VariadicType v) {});
        // dfmt on

        writelnUt(type.toStringDecl);
        type.attr.isPrimitive.shouldBeTrue;
    }

    // do not try and verify the string representation of the type.
    // It may be platform and compiler specific.
    // For example is signed char -> char.
    writelnUt(visitor.result.returnType.toStringDecl);
    visitor.result.returnType.attr.isPrimitive.shouldBeTrue;
}
