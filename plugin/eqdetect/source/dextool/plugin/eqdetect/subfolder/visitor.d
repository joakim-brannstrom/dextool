/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the functionality of traversing the given file using Visitors
and the AST imported from clang. It searches the current visiting node for the mutant
and if found (in the interval of the current cursor) it extracts the code using SnippetFinder
and generates code in the form of text by using the dsrcgen library.

TODO:
- Utilize more of the visited statements and declaration for finding all mutants.
- Track dependencies and use SnippetFinder for extracting them.
*/

module dextool.plugin.eqdetect.subfolder.visitor;

import cpptooling.analyzer.clang.ast : Visitor;
import std.stdio;
import clang.Cursor;


final class TUVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.c;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;
    CModule generatedCode;
    int offset;
    int offset_end;
    bool generated = false;

    import dextool.plugin.eqdetect.subfolder : Mutation;
    Mutation mutation;

    this(Mutation m) {
        this.generatedCode = new CModule();
        this.mutation = m;
        this.offset = m.offset_begin;
        this.offset_end = m.offset_end;
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
        generateCode(v.cursor);
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());
        generateCode(v.cursor);
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

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(ForStmt) v){
        mixin(mixinNodeLog!());
        v.accept(this);
    }
    @trusted bool inInterval(Cursor c){
        return ((c.extent.end.offset>=offset) && (c.extent.start.offset<=offset));
    }

    @trusted void generateCode(Cursor c){
        import std.path;
        if(!generated && inInterval(c) && c.extent.path.length != 0
        && baseName(mutation.path) == baseName(c.extent.path)){
            this.generatedCode.sep;

            import dextool.plugin.eqdetect.subfolder : SnippetFinder;
            auto s = SnippetFinder.generate(c, this.generatedCode, this.mutation);

            this.generatedCode.text(s);
            this.generatedCode.sep;

            generated = true;
        }
    }
}
