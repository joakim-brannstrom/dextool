/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Precise testing of the Type analyzer of the Clang AST.
*/
module test.component.analyzer.type;

import std.conv : to;
import std.format : format;
import std.typecons : scoped, Yes;
import std.variant : visit;

import unit_threaded;
import test.clang_util;
import test.helpers;

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
import cpptooling.utility.virtualfilesystem : FileName, Content;

/* These two lines are useful when debugging.
writelnUt(be.container.toString);
writelnUt(be.uml_component.toString);
*/

final class FindFunctionDeclVisitor : Visitor {
    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    /// The USR to find.
    USRType find;

    FunctionDeclResult[] result;
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

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());
        v.accept(this);

        analyzeVarDecl(v, container, indent);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        if (this.find.length == 0 || v.cursor.usr == this.find) {
            result ~= analyzeFunctionDecl(v, container, indent);
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
    visitor.find = "c:@F@__uselocale";

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.found.shouldBeTrue;
    visitor.result[0].type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.func);
    (cast(string) visitor.result[0].name).shouldEqual("__uselocale");
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
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp",
            cast(Content) format(code, getValue!string, getValue!string));
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.found.shouldBeTrue;
    visitor.result[0].type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.func);
    (cast(string) visitor.result[0].name).shouldEqual("fun");

    foreach (param; visitor.result[0].params) {
        TypeKindAttr type;
        // dfmt off
        param.visit!(
                     (TypeKindVariable v) => type = v.type,
                     (TypeKindAttr v) => type = v,
                     (VariadicType v) => type = type);
        // dfmt on

        type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.primitive);
    }

    // do not try and verify the string representation of the type.
    // It may be platform and compiler specific.
    // For example is signed char -> char.
    visitor.result[0].returnType.kind.info.kind.shouldEqual(TypeKind.Info.Kind.primitive);
}

@Name("Should be the USR of the function declaration not the typedef signature")
unittest {
    import cpptooling.data.type : LocationTag;

    enum code = "
typedef void (gun_type)(int);

// using a typedef signature to create a function
extern gun_type gun_func;
";

    // arrange
    auto visitor = new FindFunctionDeclVisitor;
    visitor.find = "c:@F@gun_func#I#";

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.found.shouldBeTrue;

    auto loc_result = visitor.container.find!LocationTag(
            visitor.result[0].type.kind.usr).front.any;
    loc_result.length.shouldEqual(1);

    auto loc = loc_result.front;
    loc.kind.shouldEqual(LocationTag.Kind.loc);
    // line 5 is the declaration of gun_func
    loc.line.shouldEqual(5);
}

@Name("Should be two pointers with the same type signature but different USRs")
unittest {
    final class VarVisitor : Visitor {
        alias visit = Visitor.visit;
        mixin generateIndentIncrDecr;

        Container container;
        VarDeclResult[] results;

        override void visit(const(TranslationUnit) v) {
            v.accept(this);
        }

        override void visit(const(VarDecl) v) {
            mixin(mixinNodeLog!());
            auto result = analyzeVarDecl(v, container, 0);
            results ~= result;
        }
    }

    enum code = "
int* p0;
int* p1;
";

    // arrange
    auto visitor = new VarVisitor;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    visitor.results.length.shouldEqual(2);
    visitor.results[0].type.kind.usr.shouldNotEqual(visitor.results[1].type.kind.usr);
}

@Name("Should be a ptr-ptr at a typedef")
unittest {
    enum code = `
typedef double MadeUp;
struct Struct {
    int x;
};

const void* const func(const MadeUp** const zzzz, const Struct** const yyyy);
`;

    import std.variant : visit;

    // arrange
    auto visitor = new FindFunctionDeclVisitor;
    visitor.find = "c:@F@func#1**1d#1**1$@S@Struct#";

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // dfmt off
    visitor.result[0].params[0]
        .visit!((TypeKindVariable a) => writelnUt(a.type.kind.usr),
                (TypeKindAttr a) => writelnUt(a.kind.usr),
                (VariadicType a) => writelnUt("variadic"));
    // dfmt on

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.found.shouldBeTrue;
    visitor.result.length.shouldNotEqual(0);

    { // assert that the found result is a func
        auto res = visitor.container.find!TypeKind(visitor.result[0].type.kind.usr).front;
        res.info.kind.shouldEqual(TypeKind.Info.Kind.func);
    }

    auto param0 = visitor.container.find!TypeKind(
            visitor.result[0].type.kind.info.params[0].usr).front;
    // assert that the found funcs first parameter is a pointer
    param0.info.kind.shouldEqual(TypeKind.Info.Kind.pointer);

    { // assert that the type pointed at is a typedef
        auto res = visitor.container.find!TypeKind(param0.info.pointee).front;
        res.usr.to!string().shouldNotEqual("File:issue.hpp Line:7 Column:45$1zzzz");
        res.info.kind.shouldEqual(TypeKind.Info.Kind.typeRef);
    }
}
