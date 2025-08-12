/**
Copyright: Copyright (c) 2016-2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Precise testing of the Type analyzer of the Clang AST.
*/
module test.component.analyzer.type;

import std.algorithm : map, filter;
import std.conv : to;
import std.format : format;
import std.range : take;
import std.typecons : scoped, Yes;

import unit_threaded;
import test.clang_util;
import blob_model;
import my.sumtype;

import cpptooling.data;

import libclang_ast.ast;
import cpptooling.analyzer.clang.analyze_helper;
import libclang_ast.context : ClangContext;
import libclang_ast.cursor_logger : logNode, mixinNodeLog;
import cpptooling.analyzer.clang.type;
import cpptooling.data.symbol : Container;
import cpptooling.data : TypeKindVariable, VariadicType, Location, USRType, toStringDecl;

/* These lines are useful when debugging.
import unit_threaded;
writelnUt(visitor.container.toString);
*/

final class TestVisitor : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    /// The USR to find.
    USRType find;

    FunctionDeclResult[] funcs;
    VarDeclResult[] vars;
    bool found;

    override void visit(scope const TranslationUnit v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Namespace v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const UnexposedDecl v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const VarDecl v) {
        mixin(mixinNodeLog!());
        v.accept(this);

        auto tmp = analyzeVarDecl(v, container, indent);
        if (this.find.length == 0 || v.cursor.usr == this.find) {
            vars ~= tmp;
            found = true;
        }
    }

    override void visit(scope const FunctionDecl v) {
        mixin(mixinNodeLog!());

        auto tmp = analyzeFunctionDecl(v, container, indent);
        if (this.find.length == 0 || v.cursor.usr == this.find) {
            funcs ~= tmp;
            found = true;
        }
    }
}

final class AllFuncVisitor : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    FunctionDeclResult[] funcs;

    override void visit(scope const TranslationUnit v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Namespace v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const UnexposedDecl v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const FunctionDecl v) {
        mixin(mixinNodeLog!());

        funcs ~= analyzeFunctionDecl(v, container, indent);
    }
}

final class TestRecordVisitor : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    RecordResult record;

    override void visit(scope const TranslationUnit v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Namespace v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const ClassDecl v) @trusted {
        mixin(mixinNodeLog!());

        record = analyzeRecord(v, container, indent);
        v.accept(this);
    }

    override void visit(scope const Constructor v) {
        mixin(mixinNodeLog!());

        analyzeConstructor(v, container, indent);
    }
}

final class TestDeclVisitor : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    override void visit(scope const TranslationUnit v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Declaration v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.store : put;

        auto type = () @trusted {
            return retrieveType(v.cursor, container, indent);
        }();
        put(type, container, indent);
        v.accept(this);
    }
}

final class TestFunctionBodyVisitor : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    FunctionDeclResult[] funcs;

    override void visit(scope const TranslationUnit v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Declaration v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Statement v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Expression v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const DeclRefExpr v) {
        mixin(mixinNodeLog!());
        import clang.Cursor : Cursor;

        Cursor ref_ = v.cursor.referenced;

        logNode(ref_, indent);

        import libclang_ast.ast.tree : dispatch;

        dispatch!Visitor(ref_, this);
    }

    override void visit(scope const FunctionDecl v) {
        mixin(mixinNodeLog!());

        funcs ~= analyzeFunctionDecl(v, container, indent);
        v.accept(this);
    }
}

final class TestUnionVisitor : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    RecordResult[] records;

    override void visit(scope const TranslationUnit v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Declaration v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Statement v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const Expression v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const UnionDecl v) {
        mixin(mixinNodeLog!());

        records ~= analyzeRecord(v, container, indent);
    }
}

final class ClassVisitor : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    /// The USR to find.
    USRType find;

    CxxMethodResult[] methods;
    FunctionDeclResult[] funcs;
    bool found;

    override void visit(scope const TranslationUnit v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const ClassDecl v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(scope const FunctionDecl v) {
        mixin(mixinNodeLog!());

        auto tmp = analyzeFunctionDecl(v, container, indent);
        if (this.find.length == 0 || v.cursor.usr == this.find) {
            funcs ~= tmp;
            found = true;
        }
    }

    override void visit(scope const CXXMethod v) @trusted {
        mixin(mixinNodeLog!());

        auto tmp = analyzeCxxMethod(v, container, indent);
        if (this.find.length == 0 || v.cursor.usr == this.find) {
            methods ~= tmp;
            found = true;
        }

        v.accept(this);
    }
}

@("Should be parameters and return type that are of primitive type")
@Tags("slow")  // execution time is >500ms
unittest {
    foreach (getValue; [
        "int", "signed int", "unsigned int", "unsigned", "char", "signed char",
        "unsigned char", "short", "signed short", "unsigned short", "long",
        "signed long", "unsigned long", "long long", "signed long long",
        "unsigned long long", "float", "double", "long double", "wchar_t", "bool"
    ]) {
        enum code = "%s fun(%s);";

        // arrange
        auto visitor = new TestVisitor;
        auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
        ctx.vfs.open(new Blob(Uri("issue.hpp"), format(code, getValue, getValue)));
        auto tu = ctx.makeTranslationUnit("issue.hpp");

        // act
        auto ast = ClangAST!(typeof(visitor))(tu.cursor);
        ast.accept(visitor);

        // assert
        checkForCompilerErrors(tu).shouldBeFalse;
        visitor.found.shouldBeTrue;
        visitor.funcs[0].type.kind.info.match!(ignore!(TypeKind.FuncInfo), (_) {
            assert(0, "wrong type");
        });
        (cast(string) visitor.funcs[0].name).shouldEqual("fun");

        foreach (param; visitor.funcs[0].params) {
            TypeKindAttr type;
            param.match!((TypeKindVariable v) => type = v.type,
                    (TypeKindAttr v) => type = v, (VariadicType v) => type = type);

            type.kind.info.match!(ignore!(TypeKind.PrimitiveInfo), (_) {
                assert(0, "wrong type");
            });
        }

        // do not try and verify the string representation of the type.
        // It may be platform and compiler specific.
        // For example is signed char -> char.
        visitor.funcs[0].returnType.kind.info.match!(ignore!(TypeKind.PrimitiveInfo), (_) {
            assert(0, "wrong type");
        });
    }
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

    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("issue.hpp"), code));
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
    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("issue.hpp"), code));
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    visitor.vars.length.shouldEqual(2);
    visitor.vars[0].type.kind.usr.shouldNotEqual(visitor.vars[1].type.kind.usr);
}

@("Should be a ptr-ptr as a typedef")
unittest {
    enum code = `
typedef double MadeUp;
struct Struct {
    int x;
};

const void* const func(const MadeUp** const zzzz, const Struct** const yyyy);
`;

    // arrange
    auto visitor = new TestVisitor;
    visitor.find = "c:@F@func#**1d#**1$@S@Struct#";

    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("issue.hpp"), code));
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    assert(visitor.funcs.length >= 1);
    assert(visitor.funcs[0].params.length >= 1);
    visitor.funcs[0].params[0].match!((TypeKindVariable a) => writelnUt(a.type.kind.usr),
            (TypeKindAttr a) => writelnUt(a.kind.usr), (VariadicType a) => writelnUt("variadic"));

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.found.shouldBeTrue;
    visitor.funcs.length.shouldNotEqual(0);

    { // assert that the found funcs is a func
        auto res = visitor.container.find!TypeKind(visitor.funcs[0].type.kind.usr).front;
        res.info.match!(ignore!(TypeKind.FuncInfo), (_) {
            assert(0, "wrong type");
        });
    }

    auto param0 = visitor.container.find!TypeKind(
            visitor.funcs[0].type.kind.info.match!(a => a.params[0].usr, _ => USRType.init)).front;
    // assert that the found funcs first parameter is a pointer
    param0.info.match!(ignore!(TypeKind.PointerInfo), (_) {
        assert(0, "wrong type");
    });

    { // assert that the type pointed at is a typedef
        auto res = visitor.container.find!TypeKind(param0.info.match!(a => a.pointee,
                _ => USRType.init)).front;
        res.usr.to!string().shouldNotEqual("File:issue.hpp Line:7 Column:45§1zzzz");
        res.info.match!(ignore!(TypeKind.TypeRefInfo), (_) {
            assert(0, "wrong type");
        });
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

    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("issue.hpp"), code));
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

    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("issue.hpp"), code));
    auto tu = ctx.makeTranslationUnit("issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);
    import std.stdio;

    writeln(visitor.container.toString);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    { // ptr to typedef
        auto r = visitor.container.find!TypeKind(
                USRType("File:issue.hpp Line:3 Column:9§1y")).front;
        r.info.match!(ignore!(TypeKind.PointerInfo), (_) {
            assert(0, "wrong type");
        });
    }

    { // ptr to typedef of func prototype
        auto r = visitor.container.find!TypeKind(
                USRType("File:issue.hpp Line:6 Column:10§1f")).front;
        r.info.match!(ignore!(TypeKind.FuncPtrInfo), (_) {
            assert(0, "wrong type");
        });
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

    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("/issue.hpp"), code));
    ctx.vfs.open(new Blob(Uri("/def.hpp"), code_def));
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
unittest {
    foreach (getValue; [
        "struct A { union { int x; }; };", "struct A { struct { int x; }; };"
    ]) {
        // arrange
        auto visitor = new TestDeclVisitor;
        auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
        ctx.vfs.open(new Blob(Uri("/issue.hpp"), getValue));
        auto tu = ctx.makeTranslationUnit("/issue.hpp");

        // act
        auto ast = ClangAST!(typeof(visitor))(tu.cursor);
        ast.accept(visitor);

        // assert
        checkForCompilerErrors(tu).shouldBeFalse;
        // didn't crash
    }
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
    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("/issue.hpp"), code));
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
    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("/issue.hpp"), code));
    auto tu = ctx.makeTranslationUnit("/issue.hpp");

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.records.length.shouldEqual(1);
    visitor.records[0].type.kind.info.match!(ignore!(TypeKind.RecordInfo), (_) {
        assert(0, "wrong type");
    });
}

@("shall be the first level of typedef as the typeref")
unittest {
    immutable code = "
typedef unsigned int ll;
typedef ll some_array[1];
const some_array& some_func();
";

    // arrange
    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("/issue.hpp"), code));
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
typedef char* string;
typedef string myString1;
typedef myString1 myString2;
typedef myString2 myString3;

void my_func(myString3 s);
";

    // arrange
    auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("/issue.hpp"), code));
    auto tu = ctx.makeTranslationUnit("/issue.hpp", ["-std=c++11"]);
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
    type.info.match!(ignore!(TypeKind.TypeRefInfo), (_) {
        assert(0, "wrong type");
    });

    // should NOT point to myString1
    // can't test the USR more specific because it is different on different
    // systems.
    type.info.match!(a => a.canonicalRef, _ => USRType.init)
        .shouldNotEqual(USRType("c:issue.hpp@T@myString1"));
}

@("shall derive the constness of the return type")
unittest {
    immutable code = "
typedef int MyInt;

class Class {
    const %s fun();
};
";

    foreach (getValue; ["int", "int*", "int&", "MyInt", "MyInt*", "MyInt&"]) {
        // arrange
        auto ctx = ClangContext(Yes.prependParamSyntaxOnly);
        ctx.vfs.open(new Blob(Uri("/issue.hpp"), format(code, getValue)));
        auto tu = ctx.makeTranslationUnit("/issue.hpp");
        auto visitor = new ClassVisitor;

        // act
        auto ast = ClangAST!(typeof(visitor))(tu.cursor);
        ast.accept(visitor);

        // assert
        checkForCompilerErrors(tu).shouldBeFalse;
        visitor.found.shouldBeTrue;

        {
            auto type2 = visitor.container.find!TypeKind(USRType("c:@S@Class@F@fun#"));
            type2.length.shouldEqual(1);
            type2.front.info.match!(ignore!(TypeKind.FuncInfo), (_) {
                assert(0, "wrong type");
            });
            type2.front.info.match!(a => a.returnAttr.isConst.shouldBeTrue, (_) {
                assert(0, "wrong type");
            });
        }
    }
}
