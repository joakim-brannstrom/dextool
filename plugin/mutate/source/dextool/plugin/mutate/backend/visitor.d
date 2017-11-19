/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.visitor;

public import dextool.clang_extensions : ValueKind;

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

struct MutationPoint {
    import clang.SourceLocation;
    import dextool.plugin.mutate.backend.vfs : Offset;
    import dextool.clang_extensions : ValueKind;

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

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());
        unaryNode(v);
    }

    override void visit(const IntegerLiteral v) {
        mixin(mixinNodeLog!());
        unaryNode(v);
    }

    void unaryNode(T)(const T v) {
        auto loc = v.cursor.location;

        if (!loc.isFromMainFile) {
            return;
        }

        // it is NOT an operator.
        addMutationPoint(v.cursor);

        v.accept(this);
    }

    // TODO should UnaryExpr also be processed?

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());
        import clang.c.Index : CXCursorKind;

        auto loc = v.cursor.location;

        if (!loc.isFromMainFile) {
            return;
        }

        auto op = getExprOperator(v.cursor);
        if (op.isValid) {
            auto s = op.sides;
            addMutationPoint(s.lhs);
            addMutationPoint(s.rhs);
        } else {
            // a call that is not an operator
            v.accept(this);
        }
    }

    override void visit(const(BinaryOperator) v) {
        mixin(mixinNodeLog!());
        import clang.c.Index : CXCursorKind;

        auto loc = v.cursor.location;

        if (!loc.isFromMainFile) {
            return;
        }

        auto op = getExprOperator(v.cursor);
        if (op.isValid) {
            auto s = op.sides;
            addMutationPoint(s.lhs);
            addMutationPoint(s.rhs);
        }
    }

    void addMutationPoint(const(Cursor) c) {
        import std.algorithm : among;
        import clang.c.Index : CXCursorKind;
        import dextool.plugin.mutate.backend.vfs;

        if (!c.isValid)
            return;

        const auto kind = exprValueKind(getUnderlyingExprNode(c));
        SourceLocation loc = c.location;
        auto spelling = exprSpelling(c);

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);
        auto p = MutationPoint(kind, offs, spelling, loc.presumed);
        exprs.put(p);
    }

    /**
     * trusted: the tokens do not escape the function.
     */
    static string exprSpelling(const Cursor c) @trusted {
        import std.algorithm : map;
        import std.range : takeOne;

        import clang.c.Index : CXCursorKind;

        if (c.kind == CXCursorKind.integerLiteral) {
            auto toks = c.tokens;
            if (toks.length == 0)
                return c.spelling;
            return toks.map!(a => a.spelling).takeOne.front;
        } else {
            return c.spelling;
        }
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
