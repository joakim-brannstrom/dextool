/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module test.component.generator;

import std.conv : to;
import std.format : format;
import std.typecons : scoped, Yes;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import unit_threaded;
import test.clang_util;
import blob_model;

import dextool.type;
import dextool.utility;

import cpptooling.data;
import cpptooling.data.symbol : Container;

import cpptooling.analyzer.clang.ast : Visitor, ClangAST;

import cpptooling.generator.gtest;
import cpptooling.generator.gmock;

version (unittest) {
    import unit_threaded.assertions : shouldEqual;
}

final class TestVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    CppClass[] classes;

    private CppNsStack ns_stack;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());

        () @trusted { ns_stack ~= CppNs(v.cursor.spelling); }();
        // pop the stack when done
        scope (exit)
            ns_stack = ns_stack[0 .. $ - 1];

        v.accept(this);
    }

    override void visit(const(ClassDecl) v) {
        visitRecord(v);
    }

    override void visit(const(StructDecl) v) {
        visitRecord(v);
    }

    void visitRecord(T)(const T v) @trusted {
        import cpptooling.analyzer.clang.analyze_helper : ClassVisitor, analyzeRecord;

        mixin(mixinNodeLog!());

        auto result = analyzeRecord(v, container, indent + 1);
        debug logger.trace("class: ", result.name);

        if (v.cursor.isDefinition) {
            auto visitor = scoped!ClassVisitor(v, ns_stack, result, container, indent + 1);
            v.accept(visitor);

            classes ~= visitor.root;
        }
    }
}

@("shall generate a pretty printer for a PODs public members")
unittest {
    immutable code = "
struct pod {
    int x;
};
";

    // arrange
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("/issue.hpp"), code));
    auto tu = ctx.makeTranslationUnit("/issue.hpp");
    auto visitor = new TestVisitor;
    auto codegen = new CppModule;

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);
    visitor.classes.length.shouldEqual(1);
    generateGtestPrettyPrintHdr(visitor.classes[0].fullyQualifiedName, codegen);
    generateGtestPrettyPrintImpl(visitor.classes[0].memberPublicRange,
            visitor.classes[0].fullyQualifiedName, codegen);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    codegen.render.shouldEqual(`    void PrintTo(const pod& x0, ::std::ostream* os);

    void PrintTo(const pod& x0, ::std::ostream* os) {
        *os << "x:" << ::testing::PrintToString(x0.x);
    }

`);
}

@("shall generate an interface where protected/private are made public and non-virtual are removed")
unittest {
    immutable code = "
class Sneaky {
public:
    void pub_nonvirt();
    virtual void pub();
protected:
    void prot_nonvirt();
    virtual void prot();
private:
    void priv_nonvirt();
    virtual void priv();
};
";

    // arrange
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.vfs.open(new Blob(Uri("/issue.hpp"), code));
    auto tu = ctx.makeTranslationUnit("/issue.hpp");
    auto visitor = new TestVisitor;
    auto codegen = new CppModule;

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);
    visitor.classes.length.shouldEqual(1);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    auto mock = makeGmock(visitor.classes[0]);
    mock.toString.shouldEqual(`class Sneaky { // Pure
public:
  virtual void priv() = 0;
  virtual void prot() = 0;
  virtual void pub() = 0;
}; //Class:Sneaky`);
}
