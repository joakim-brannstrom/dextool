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
import logger = std.experimental.logger;

import cpptooling.analyzer.clang.ast : Visitor;
import dextool.type : AbsolutePath, Path, FileName;

@safe:

string makeAndCheckLocation() {
    return q{auto loc = v.cursor.location;
    if (!val_loc.shouldAnalyze(loc.path)) {
        return;
    }};
}

/** Find all mutation points that affect a whole expression.
 *
 * TODO change the name of the class. It is more than just an expression
 * visitor.
 */
final class ExpressionVisitor : Visitor {
    import std.array : Appender;
    import clang.Cursor : Cursor;
    import clang.SourceLocation : SourceLocation;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dextool.clang_extensions;
    import dextool.plugin.mutate.backend.database : MutationPointEntry;
    import dextool.plugin.mutate.backend.interface_ : ValidateLoc;
    import dextool.plugin.mutate.backend.type : MutationPoint, SourceLoc;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    private Appender!(MutationPointEntry[]) exprs;
    private bool[Path] files;
    private ValidateLoc val_loc;

    const(MutationPointEntry[]) mutationPoints() {
        return exprs.data;
    }

    Path[] mutationPointFiles() @trusted {
        import std.array : array;

        return files.byKey.array();
    }

    /**
     * Params:
     *  restrict = only analyze files starting with this path
     */
    this(ValidateLoc val_loc) nothrow {
        this.val_loc = val_loc;
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
        mixin(makeAndCheckLocation);

        addStatement(v);
        addExprMutationPoint(getExprOperator(v.cursor));

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
        mixin(makeAndCheckLocation);

        // it is NOT an operator.
        addMutationPoint(v.cursor);
        addExprMutationPoint(getExprOperator(v.cursor));

        v.accept(this);
    }

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());
        mixin(makeAndCheckLocation);

        // #SPC-plugin_mutate_mutations_statement_del-call_expression
        addStatement(v);

        auto op = getExprOperator(v.cursor);
        if (op.isValid) {
            addExprMutationPoint(op);
            auto s = op.sides;
            addMutationPoint(s.lhs);
            addMutationPoint(s.rhs);
        }

        v.accept(this);
    }

    override void visit(const(BreakStmt) v) {
        mixin(mixinNodeLog!());
        mixin(makeAndCheckLocation);

        addStatement(v);
        v.accept(this);
    }

    override void visit(const(BinaryOperator) v) {
        mixin(mixinNodeLog!());
        mixin(makeAndCheckLocation);

        auto op = getExprOperator(v.cursor);
        if (op.isValid) {
            addExprMutationPoint(op);
            auto s = op.sides;
            addMutationPoint(s.lhs);
            addMutationPoint(s.rhs);
        }

        v.accept(this);
    }

    override void visit(const(CompoundAssignOperator) v) {
        mixin(mixinNodeLog!());
        import std.range : dropOne;
        import cpptooling.analyzer.clang.ast.tree : dispatch;

        mixin(makeAndCheckLocation);

        // not adding the left side because it results in nonsense mutations for UOI.
        foreach (child; v.cursor.children.dropOne) {
            dispatch(child, this);
        }
    }

    // TODO ugly duplication between this and addExprMutationPoint. Fix it.
    void addMutationPoint(const(Cursor) c) {
        import std.algorithm : map;
        import std.array : array;
        import std.range : chain;
        import dextool.plugin.mutate.backend.type : Offset;
        import dextool.plugin.mutate.backend.utility;

        if (!c.isValid)
            return;

        const auto kind = exprValueKind(getUnderlyingExprNode(c));

        SourceLocation loc = c.location;

        // a bug in getExprOperator makes the path for a ++ which is overloaded
        // is null.
        auto path = loc.path.Path;
        if (path is null)
            return;
        files[path] = true;

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);

        auto m0 = absMutations;
        auto m1 = kind == ValueKind.lvalue ? uoiLvalueMutations : uoiRvalueMutations;
        auto m = chain(m0, m1).map!(a => Mutation(a)).array();
        auto p2 = MutationPointEntry(MutationPoint(offs, m), path,
                SourceLoc(loc.line, loc.column));
        exprs.put(p2);
    }

    void addExprMutationPoint(const(Operator) op_) {
        import std.algorithm : map;
        import std.array : array;
        import std.range : chain;
        import dextool.plugin.mutate.backend.type : Offset;
        import dextool.plugin.mutate.backend.utility;

        if (!op_.isValid)
            return;

        SourceLocation loc = op_.cursor.location;
        // a bug in getExprOperator makes the path for a ++ which is overloaded
        // is null.
        auto path = loc.path.Path;
        if (path is null)
            return;
        files[path] = true;

        // construct the mutations points to allow the delegates to fill with data
        auto sloc = SourceLoc(loc.line, loc.column);
        MutationPointEntry lhs, rhs, op, expr;

        void sidesPoint() {
            auto opsr = op_.location.spelling;
            auto sr = op_.cursor.extent;

            auto offs_rhs = Offset(opsr.offset, sr.end.offset);
            rhs = MutationPointEntry(MutationPoint(offs_rhs, null), path, sloc);

            auto offs_lhs = Offset(sr.start.offset, cast(uint)(opsr.offset + op_.length));
            lhs = MutationPointEntry(MutationPoint(offs_lhs, null), path, sloc);
        }

        void opPoint() {
            auto sr = op_.location.spelling;
            auto offs = Offset(sr.offset, cast(uint)(sr.offset + op_.length));
            op = MutationPointEntry(MutationPoint(offs, null), path, sloc);
        }

        void exprPoint() {
            auto sr = op_.cursor.extent;
            auto offs_expr = Offset(sr.start.offset, sr.end.offset);
            expr = MutationPointEntry(MutationPoint(offs_expr, null), path, sloc);
        }

        sidesPoint();
        opPoint();
        exprPoint();

        void cor() {
            // delete rhs
            rhs.mp.mutations ~= [Mutation(Mutation.Kind.corLhs)];

            // delete lhs
            lhs.mp.mutations ~= [Mutation(Mutation.Kind.corRhs)];

            if (auto v = op_.kind in isCor) {
                op.mp.mutations ~= corOpMutations(*v).map!(a => Mutation(a)).array();
                expr.mp.mutations ~= corExprMutations(*v).map!(a => Mutation(a)).array();
            }
        }

        void ror() {
            auto mut = rorMutations(op_.kind);
            op.mp.mutations ~= mut.op.map!(a => Mutation(a)).array();
            expr.mp.mutations ~= Mutation(mut.expr);
        }

        if (op_.kind in isRor)
            ror();
        else if (auto v = op_.kind in isLcr) {
            op.mp.mutations ~= lcrMutations(*v).map!(a => Mutation(a)).array();
            cor();
        } else if (auto v = op_.kind in isAor)
            op.mp.mutations ~= aorMutations(*v).map!(a => Mutation(a)).array();
        else if (auto v = op_.kind in isAorAssign)
            op.mp.mutations ~= aorAssignMutations(*v).map!(a => Mutation(a)).array();

        exprs.put(lhs);
        exprs.put(rhs);
        exprs.put(op);
        exprs.put(expr);
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
        addStatement(v);
        v.accept(this);
    }

    void addStatement(T)(const(T) v) {
        import std.algorithm : map;
        import std.array : array;
        import dextool.plugin.mutate.backend.type : Offset;
        import dextool.plugin.mutate.backend.utility;

        auto loc = v.cursor.location;
        if (!val_loc.shouldAnalyze(loc.path)) {
            return;
        }

        auto path = loc.path.Path;
        if (path is null)
            return;
        files[path] = true;

        auto offs = calcOffset(v);
        auto m = stmtDelMutations.map!(a => Mutation(a)).array();

        exprs.put(MutationPointEntry(MutationPoint(offs, m), path,
                SourceLoc(loc.line, loc.column)));
    }
}

private:

import clang.c.Index : CXTokenKind;
import dextool.plugin.mutate.backend.type : Offset;

// trusted: the tokens do not escape this function.
Offset calcOffset(T)(const(T) v) @trusted {
    import clang.c.Index : CXTokenKind;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

    Offset rval;

    auto sr = v.cursor.extent;
    rval = Offset(sr.start.offset, sr.end.offset);

    static if (is(T == CallExpr) || is(T == BreakStmt)) {
        import clang.Token;

        // TODO this is extremly inefficient. change to a more localized cursor
        // or even better. Get the tokens at the end.
        auto arg = v.cursor.translationUnit.cursor;

        rval.end = findTokenOffset(arg.tokens, rval, CXTokenKind.punctuation, ";");
    }

    return rval;
}

/// trusted: trusting the impl in clang.
uint findTokenOffset(T)(T toks, Offset sr, CXTokenKind kind, string spelling) @trusted {
    foreach (ref t; toks) {
        if (t.location.offset >= sr.end) {
            if (t.kind == kind && t.spelling == spelling) {
                return t.extent.end.offset;
            }
            break;
        }
    }

    return sr.end;
}
