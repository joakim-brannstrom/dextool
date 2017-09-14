/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file tests the class visitor for C++.
*/
module test.component.analyzer.cpp_class_visitor;

import std.conv : to;
import std.format : format;
import std.typecons : scoped, Yes;
import std.variant : visit;

import unit_threaded;
import test.clang_util;
import test.helpers;

// TODO this is a mega import. Reduce it
import cpptooling.data;

import cpptooling.analyzer.clang.ast;
import cpptooling.analyzer.clang.analyze_helper;
import cpptooling.analyzer.clang.context : ClangContext;
import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
import cpptooling.analyzer.clang.type;
import cpptooling.data.symbol : Container;
import cpptooling.data.representation;
import cpptooling.data : TypeKindVariable, VariadicType, Location, CppNsStack,
    USRType, toStringDecl;
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

    CppClass[] classes;
    bool found;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(ClassDecl) v) @trusted {
        mixin(mixinNodeLog!());

        import std.typecons : scoped;
        import cpptooling.analyzer.clang.analyze_helper : ClassVisitor;
        import cpptooling.analyzer.clang.type : retrieveType;
        import cpptooling.analyzer.clang.store : put;

        ///TODO add information if it is a public/protected/private class.
        ///TODO add metadata to the class if it is a definition or declaration

        if (v.cursor.isDefinition) {
            auto visitor = scoped!ClassVisitor(v, CppNsStack.init, container, indent + 1);
            v.accept(visitor);
            classes ~= visitor.root;
        } else {
            auto type = retrieveType(v.cursor, container, indent);
            put(type, container, indent);
        }
    }
}

@("shall be a class with a method using the typedef as return value")
unittest {
    // This test result in the return type for some_func being
    // `const unsigned int( &x)[1]` in clang 3.7/3.8.
    // But seems to work in 3.9

    immutable code = "
namespace ns1 {
typedef unsigned int some_unsigned;
typedef some_unsigned the_type;
typedef the_type some_array[1];
}

class Class {
public:
    const ns1::some_array& some_func();
};
";

    // arrange
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.openAndWrite(cast(FileName) "/issue.hpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("/issue.hpp");
    auto visitor = new TestVisitor;
    //visitor.find = "c:@F@some_func#";

    // act
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    checkForCompilerErrors(tu).shouldBeFalse;
    visitor.classes.length.shouldEqual(1);
    visitor.classes[0].methodPublicRange.length.shouldEqual(1);

    import std.variant : visit;

    CppMethod method;

    // dfmt off
    visitor.classes[0].methodPublicRange[0].visit!(
        (const CppMethod a) { method = cast(CppMethod) a; return; },
        (const CppMethodOp a) => 0.shouldEqual(1),
        (const CppCtor a) => 0.shouldEqual(1),
        (const CppDtor a) => 0.shouldEqual(1));
    // dfmt on

    method.returnType.toStringDecl("x").shouldEqual("const ns1::some_array &x");
}
