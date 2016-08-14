/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module test.component.plantuml_activity;

import std.typecons : Flag, Yes;

import unit_threaded;
import test.clang_util;

import application.types;
import cpptooling.analyzer.kind : TypeKind;
import cpptooling.analyzer.type : USRType;
import cpptooling.analyzer.clang.ast : ClangAST;
import cpptooling.analyzer.clang.context;
import cpptooling.data.symbol.container : Container;
import cpptooling.utility.virtualfilesystem : FileName, Content;

import plugin.backend.plantuml;

@Name("Should be an activity diagram")
unittest {
    enum code = `
void fun() {
    int i;

    if (true) {
    }
}`;

    // arrange
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    ctx.virtualFileSystem.put(cast(FileName) "/act1.cpp", cast(Content) code);
    auto tu = ctx.makeTranslationUnit("/act1.cpp");
    tu.checkForCompilerErrors.shouldBeFalse;

    // act
    auto visitor = new UMLActivity;
    auto ast = new ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    // assert
    writelnUt(visitor.diagram.render);
}
