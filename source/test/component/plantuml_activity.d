/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module test.component.plantuml_activity;

import unit_threaded;
import test.clang_util;

import application.types;
import cpptooling.analyzer.kind : TypeKind;
import cpptooling.analyzer.type : USRType;
import cpptooling.analyzer.clang.ast : ClangAST;
import cpptooling.analyzer.clang.context;
import cpptooling.data.symbol.container : Container;

import plugin.backend.plantuml;

@Name("Should be an activity diagram")
unittest {
    enum code = `
void fun() {
    int i;

    if (true) {
    }
}`;

    auto ctx = ClangContext.fromString!"/act1.cpp"(code);
    ctx.checkForCompilerErrors.shouldBeFalse;

    auto visitor = new UMLActivity;
    auto ast = new ClangAST!(typeof(visitor))(ctx.cursor);
    ast.accept(visitor);

    writelnUt(visitor.diagram.render);
}
