/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
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

/* These lines are useful when debugging.
import unit_threaded;
writelnUt(visitor.container.toString);
*/

final class TestVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    /// The USR to find.
    USRType find;

    FunctionDeclResult[] funcs;
    VarDeclResult[] vars;
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

        auto tmp = analyzeVarDecl(v, container, indent);
        if (this.find.length == 0 || v.cursor.usr == this.find) {
            vars ~= tmp;
            found = true;
        }
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto tmp = analyzeFunctionDecl(v, container, indent);
        if (this.find.length == 0 || v.cursor.usr == this.find) {
            funcs ~= tmp;
            found = true;
        }
    }
}

final class TestRecordVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    RecordResult record;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(ClassDecl) v) {
        mixin(mixinNodeLog!());

        record = analyzeRecord(v, container, indent);
        v.accept(this);
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());

        analyzeConstructor(v, container, indent);
    }
}

final class TestDeclVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.store : put;

        auto type = () @trusted{
            return retrieveType(v.cursor, container, indent);
        }();
        put(type, container, indent);
        v.accept(this);
    }
}

final class TestFunctionBodyVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    FunctionDeclResult[] funcs;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());
        import clang.Cursor : Cursor;

        Cursor ref_ = v.cursor.referenced;

        logNode(ref_, indent);

        import cpptooling.analyzer.clang.ast.tree : dispatch;

        dispatch!Visitor(ref_, this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        funcs ~= analyzeFunctionDecl(v, container, indent);
        v.accept(this);
    }
}

final class TestUnionVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    RecordResult[] records;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(UnionDecl) v) {
        mixin(mixinNodeLog!());

        records ~= analyzeRecord(v, container, indent);
    }
}

version (linux) {
    @("Should be a type of kind 'func'")
    unittest {
        enum code = `
        #include <clocale>

        namespace dextool__gnu_cxx {
        extern "C" __typeof(uselocale) __uselocale;
        }
        `;

        // arrange
        auto visitor = new TestVisitor;
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
        visitor.funcs[0].type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.func);
        (cast(string) visitor.funcs[0].name).shouldEqual("__uselocale");
    }
}

@("Should be parameters and return type that are of primitive type")
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
    auto visitor = new TestVisitor;
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
    visitor.funcs[0].type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.func);
    (cast(string) visitor.funcs[0].name).shouldEqual("fun");

    foreach (param; visitor.funcs[0].params) {
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
    visitor.funcs[0].returnType.kind.info.kind.shouldEqual(TypeKind.Info.Kind.primitive);
}

@("Should be the USR of the function declaration not the typedef signature")
unittest {
    import cpptooling.data.type : LocationTag;

    enum code = "
typedef void (gun_type)(int);

// using a typedef signature to create a function
extern gun_type gun_func;
";

    // arrange
    auto visitor = new TestVisitor;
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

    auto loc_result = visitor.container.find!LocationTag(visitor.funcs[0].type.kind.usr).front.any;
    loc_result.length.shouldEqual(1);

    auto loc = loc_result.front;
    loc.kind.shouldEqual(LocationTag.Kind.loc);
    // line 5 is the declaration of gun_func
    loc.line.shouldEqual(5);
}

@("Should be two pointers with the same type signature but different USRs")
unittest {
    enum code = "
int* p0;
int* p1;
";

    // arrange
    auto visitor = new TestVisitor;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    visitor.vars.length.shouldEqual(2);
    visitor.vars[0].type.kind.usr.shouldNotEqual(visitor.vars[1].type.kind.usr);
}

@("Should be a ptr-ptr at a typedef")
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
    auto visitor = new TestVisitor;
    visitor.find = "c:@F@func#1**1d#1**1$@S@Struct#";

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // dfmt off
    visitor.funcs[0].params[0]
        .visit!((TypeKindVariable a) => writelnUt(a.type.kind.usr),
                (TypeKindAttr a) => writelnUt(a.kind.usr),
                (VariadicType a) => writelnUt("variadic"));
    // dfmt on

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.found.shouldBeTrue;
    visitor.funcs.length.shouldNotEqual(0);

    { // assert that the found funcs is a func
        auto res = visitor.container.find!TypeKind(visitor.funcs[0].type.kind.usr).front;
        res.info.kind.shouldEqual(TypeKind.Info.Kind.func);
    }

    auto param0 = visitor.container.find!TypeKind(
            visitor.funcs[0].type.kind.info.params[0].usr).front;
    // assert that the found funcs first parameter is a pointer
    param0.info.kind.shouldEqual(TypeKind.Info.Kind.pointer);

    { // assert that the type pointed at is a typedef
        auto res = visitor.container.find!TypeKind(param0.info.pointee).front;
        res.usr.to!string().shouldNotEqual("File:issue.hpp Line:7 Column:45§1zzzz");
        res.info.kind.shouldEqual(TypeKind.Info.Kind.typeRef);
    }
}

@("Should be the same USR for the declaration and definition of a function")
unittest {
    enum code = `
void fun();
void fun() {}

extern "C" void gun();
void gun() {}
`;

    // arrange
    auto visitor = new TestVisitor;
    visitor.find = "c:@F@fun";

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.container.find!TypeKind(USRType("c:@F@fun#")).length.shouldEqual(1);
    visitor.container.find!TypeKind(USRType("c:@F@gun")).length.shouldEqual(1);
}

@("Should be a unique USR for the ptr with a ref to the typedef (my_int)")
unittest {
    enum code = `
typedef int my_int;
my_int *y;

typedef void (fun_ptr)();
fun_ptr *f;
`;

    // arrange
    auto visitor = new TestVisitor;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    { // ptr to typedef
        auto r = visitor.container.find!TypeKind(
                USRType("File:issue.hpp Line:3 Column:9§1y")).front;
        r.info.kind.shouldEqual(TypeKind.Info.Kind.pointer);
    }

    { // ptr to typedef of func prototype
        auto r = visitor.container.find!TypeKind(
                USRType("File:issue.hpp Line:6 Column:10§1f")).front;
        r.info.kind.shouldEqual(TypeKind.Info.Kind.funcPtr);
    }
}

@("Should be a forward declaration and definition separated")
unittest {
    import cpptooling.data.type : LocationTag;

    enum code = "class A;
class A_ByCtor { A_ByCtor(A a); };";
    enum code_def = `class A {};`;

    // arrange
    auto visitor = new TestRecordVisitor;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/issue.hpp", cast(Content) code);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/def.hpp", cast(Content) code_def);
    auto tu0 = ctx.makeTranslationUnit("/issue.hpp");
    auto tu1 = ctx.makeTranslationUnit("/def.hpp");

    // act
    auto ast0 = ClangAST!(typeof(visitor))(tu0.cursor);
    ast0.accept(visitor);
    auto ast1 = ClangAST!(typeof(visitor))(tu1.cursor);
    ast1.accept(visitor);

    // assert
    checkForCompilerErrors(tu0).shouldBeFalse;
    checkForCompilerErrors(tu1).shouldBeFalse;

    auto loc = visitor.container.find!LocationTag(visitor.record.type.kind.usr).front.get;

    loc.hasDeclaration.shouldBeTrue;
    loc.declaration.shouldEqual(LocationTag(Location("/issue.hpp", 1, 7)));

    loc.hasDefinition.shouldBeTrue;
    loc.definition.shouldEqual(LocationTag(Location("/def.hpp", 1, 7)));
}

@("Should not crash on an anonymous type")
@Values("struct A { union { int x; }; };", "struct A { struct { int x; }; };")
unittest {
    // arrange
    auto visitor = new TestDeclVisitor;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/issue.hpp", cast(Content) getValue!string);
    auto tu = ctx.makeTranslationUnit("/issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    // didn't crash
}

@("Should be a builtin with a function name")
unittest {
    immutable code = "
void f() {
    __builtin_huge_valf();
}

class A {
    void my_builtin() {
        __builtin_huge_valf();
    }
};
";

    // arrange
    auto visitor = new TestFunctionBodyVisitor;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("/issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.funcs.length.shouldEqual(3);
    visitor.funcs[1].name.shouldEqual("__builtin_huge_valf");
    visitor.funcs[2].name.shouldEqual("__builtin_huge_valf");
}

@("Should be an union analysed and classified as a record")
unittest {
    immutable code = "
struct A {
    union {
        char a;
        int b;
    };
};";

    // arrange
    auto visitor = new TestUnionVisitor;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("/issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.records.length.shouldEqual(1);
    visitor.records[0].type.kind.info.kind.shouldEqual(TypeKind.Info.Kind.record);
}

@("shall be the first level of typedef as the typeref")
unittest {
    immutable code = "
typedef unsigned int ll;
typedef ll some_array[1];
const some_array& some_func();
";

    // arrange
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("/issue.hpp");
    auto visitor = new TestVisitor;
    visitor.find = "c:@F@some_func#";

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.funcs.length.shouldEqual(1);
    visitor.funcs[0].returnType.toStringDecl("x").shouldEqual("const some_array &x");
}

@("shall be a TypeRef with a canonical ref referencing the type at the end of the typedef chain")
unittest {
    immutable code = "
#include <string>
typedef std::string myString1;
typedef myString1 myString2;
typedef myString2 myString3;

void my_func(myString3 s);
";

    // arrange
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("/issue.hpp");
    auto visitor = new TestVisitor;

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.found.shouldBeTrue;

    auto type2 = visitor.container.find!TypeKind(USRType("c:issue.hpp@T@myString3"));
    type2.length.shouldEqual(1);
    auto type = type2.front;
    type.info.kind.shouldEqual(TypeKind.Info.Kind.typeRef);

    // should NOT point to myString1
    // can't test the USR more specific because it is different on different
    // systems.
    type.info.canonicalRef.dup.shouldNotEqual(USRType("c:issue.hpp@T@myString1"));
}
