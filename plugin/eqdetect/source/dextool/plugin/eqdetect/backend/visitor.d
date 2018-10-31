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

module dextool.plugin.eqdetect.backend.visitor;

import clang.Cursor;
import cpptooling.analyzer.clang.ast : Visitor;
import dextool.plugin.mutate.backend.type : Offset;

@safe:

final class TUVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.c : CModule;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;
    CModule generatedSource;
    CModule generatedMutation;
    bool generated = false;
    string function_name;
    string[] function_params;

    import std.typecons : Tuple;

    Offset[] offsets;

    import dextool.plugin.eqdetect.backend : Mutation;

    Mutation mutation;

    this(Mutation m) {
        this.generatedSource = new CModule();
        this.generatedMutation = new CModule();
        this.mutation = m;
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());
        saveOffsets(v.cursor);
        v.accept(this);
    }

    override void visit(const(ParmDecl) v) {
        mixin(mixinNodeLog!());
        saveOffsets(v.cursor);
        v.accept(this);
    }

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());
        saveOffsets(v.cursor);
        v.accept(this);
    }

    override void visit(const(CxxMethod) v) {
        mixin(mixinNodeLog!());
        saveOffsets(v.cursor);
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());
        saveOffsets(v.cursor);
        generateCode(v.cursor); //TODO: call on this elsewhere
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        saveOffsets(v.cursor);
        v.accept(this);
    }

    override void visit(const(MemberRefExpr) v) {
        mixin(mixinNodeLog!());
        saveOffsets(v.cursor);
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

    //TODO: Fix ugly implementation, doesn't work in all cases (ex. int i = 0)
    void saveOffsets(Cursor c) {
        import std.path : buildNormalizedPath;
        import std.file : getcwd;

        if (buildNormalizedPath(getcwd(), mutation.path) == c.definition.location.path
                && buildNormalizedPath(getcwd(), mutation.path) == c.extent.path) {
            Offset offset;
            import std.stdio : File, writeln;
            import std.file : getSize;
            import std.string : indexOf;

            auto file = File(c.extent.path, "r");
            auto buffer = file.rawRead(new char[getSize(c.extent.path)]);
            buffer = buffer[c.extent.start.offset .. c.extent.end.offset];
            int name_offset = cast(int) indexOf(buffer, c.spelling);
            offset.begin = c.extent.start.offset + name_offset;
            offset.end = c.extent.end.offset - (
                    c.extent.end.offset - c.extent.start.offset - cast(
                    uint) c.spelling.length - name_offset);

            offsets ~= offset;
        }
    }

    void generateCode(Cursor c) {
        import std.path : baseName;

        if (!generated && c.extent.path.length != 0
                && baseName(mutation.path) == baseName(c.extent.path)) {
            import dextool.plugin.eqdetect.backend : SnippetFinder;

            auto s = SnippetFinder.generateSource(c, this.mutation);

            this.generatedSource.text(s);

            getFunctionDecl(c);

            generated = true;
        }
    }

    @trusted void getFunctionDecl(Cursor c) {
        import clang.c.Index;

        function_name = c.tokens[1].spelling;

        foreach (child; c.children) {
            if (child.kind == CXCursorKind.parmDecl) {
                string tmp = "";
                if (child.tokens[1].spelling == "*") {
                    tmp = child.tokens[0].spelling ~ "*";
                } else {
                    tmp = child.tokens[0].spelling;
                }
                function_params = function_params ~ tmp;
            }
        }
    }
}
