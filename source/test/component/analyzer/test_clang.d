/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module test the visitor, ast and interaction with Clang.
*/
module test.component.analyzer.test_clang;

import std.typecons : Yes;

import test.clang_util;
import test.helpers;

import cpptooling.analyzer.clang.ast;
import cpptooling.analyzer.clang.context : ClangContext;
import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
import cpptooling.utility.virtualfilesystem : FileName, Content;

version (unittest) {
    import unit_threaded : shouldEqual, shouldBeFalse, shouldBeTrue;
}

final class TestVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    bool underlyingIsEnum;
    string typedefSpelling;

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(TypedefDecl) v) {
        mixin(mixinNodeLog!());

        if (v.cursor.spelling == "MyType") {
            typedefSpelling = v.cursor.spelling;
            underlyingIsEnum = v.cursor.isUnderlyingTypeEnum;
        }
    }
}

@("shall detect that the underlying of the typedef is an enum kind")
unittest {
    immutable code = `
enum EnumFoo {
    Foo
};

    typedef EnumFoo MyType;
`;

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
    visitor.typedefSpelling.shouldEqual("MyType");
    visitor.underlyingIsEnum.shouldBeTrue;
}
