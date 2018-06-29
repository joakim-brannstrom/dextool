/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

TODO:Description of file
*/

module dextool.plugin.eqdetect.subfolder.visitor;

import cpptooling.analyzer.clang.ast : Visitor;
import std.stdio;

final class TUVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.c;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    CModule generatedCode;

    this() {
        this.generatedCode = new CModule();
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Directive) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Preprocessor) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Reference) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(ForStmt) v){
        mixin(mixinNodeLog!());

        import dextool.plugin.eqdetect.subfolder : SnippetFinder;
        import std.conv: to;

        generatedCode.text("Line: " ~ to!string(v.cursor.extent.start.line));
        generatedCode.sep;

        auto s = SnippetFinder.generate(v.cursor, this.generatedCode);

        generatedCode.text(s);
        generatedCode.sep;

        v.accept(this);
    }
}
