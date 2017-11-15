/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.visitor;

import cpptooling.analyzer.clang.ast : Visitor;

@safe:

/** Extract a specific mutation point for operators.
 */
final class ExpressionOpVisitor : Visitor {
    import std.array : Appender;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dextool.clang_extensions;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    alias OpFilter = bool function(OpKind);

    private const OpFilter op_filter;
    private Appender!(Operator[]) ops;

    this(OpFilter op_filter) {
        this.op_filter = op_filter;
    }

    Operator[] operators() {
        return ops.data;
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

        if (!v.location.isFromMainFile) {
            return;
        }

        auto op = getExprOperator(v.cursor);
        if (op.isValid && op_filter(op.kind)) {
            ops.put(op);
        }

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
}

enum ValueKind {
    lvalue,
    rvalue,
}

struct MutationPoint {
    import clang.SourceLocation;
    import dextool.plugin.mutate.backend.vfs;

    ValueKind kind;

    Offset offset;
    string spelling;
    SourceLocation.Location2 location;
}

/** Find all mutation points that affect a whole expression.
 *
 */
final class ExpressionVisitor : Visitor {
    import std.array : Appender;
    import clang.Cursor : Cursor;
    import clang.SourceLocation : SourceLocation;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dextool.clang_extensions;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    private Appender!(const(MutationPoint)[]) exprs;

    auto mutationPoints() {
        return exprs.data;
    }

    this() {
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

    override void visit(const(DeclRefExpr) v) @trusted {
        mixin(mixinNodeLog!());
        import clang.c.Index : CXCursorKind;

        auto loc = v.cursor.location;

        if (!loc.isFromMainFile) {
            return;
        }

        auto ref_ = v.cursor.referenced;
        if (ref_.kind != CXCursorKind.varDecl)
            return;

        addMutationPoint(v.cursor, loc, v.cursor.spelling, ValueKind.lvalue);

        v.accept(this);
    }

    void addMutationPoint(const(Cursor) c, SourceLocation loc, string spelling, ValueKind kind) {
        import dextool.plugin.mutate.backend.vfs;

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);
        auto p = MutationPoint(kind, offs, spelling, loc.presumed);
        exprs.put(p);
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
}
