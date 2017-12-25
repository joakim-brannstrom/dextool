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

// these imports are used in visitors. They are here to avoid cluttering the
// individual visitors with a wall of text of imports.
import clang.Cursor : Cursor;
import clang.SourceLocation : SourceLocation;
import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
import dextool.plugin.mutate.backend.database : MutationPointEntry;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc;
import dextool.plugin.mutate.backend.type : MutationPoint, SourceLoc;

@safe:

/** Find all mutation points that affect a whole expression.
 *
 * TODO change the name of the class. It is more than just an expression
 * visitor.
 */
final class ExpressionVisitor : Visitor {
    import std.array : array;
    import cpptooling.analyzer.clang.ast;
    import dextool.clang_extensions : getExprOperator, OpKind;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    private AnalyzeResult result;
    private ValidateLoc val_loc;
    private Transform transf;

    /**
     * Params:
     *  restrict = only analyze files starting with this path
     */
    this(ValidateLoc val_loc) nothrow {
        this.result = new AnalyzeResult;
        this.val_loc = val_loc;
        this.transf = Transform(result, val_loc);

        import dextool.plugin.mutate.backend.utility : stmtDelMutations,
            absMutations, uoiLvalueMutations, uoiRvalueMutations;

        transf.stmtCallback ~= () => stmtDelMutations;

        transf.unaryInjectCallback ~= (ValueKind k) => absMutations;
        transf.binaryOpLhsCallback ~= (OpKind k) => absMutations;
        transf.binaryOpRhsCallback ~= (OpKind k) => absMutations;

        transf.unaryInjectCallback ~= (ValueKind k) => k == ValueKind.lvalue
            ? uoiLvalueMutations : uoiRvalueMutations;

        import std.algorithm : map;
        import dextool.plugin.mutate.backend.type : Mutation;
        import dextool.plugin.mutate.backend.utility : isLcr, lcrMutations,
            isAor, aorMutations, isAorAssign, aorAssignMutations, isRor,
            rorMutations, isCor, corOpMutations, corExprMutations;

        // TODO refactor so array() can be removed. It is an unnecessary allocation
        transf.binaryOpOpCallback ~= (OpKind k) {
            if (auto v = k in isLcr)
                return lcrMutations(*v).map!(a => cast(Mutation.Kind) a).array();
            else
                return null;
        };

        transf.binaryOpOpCallback ~= (OpKind k) {
            if (auto v = k in isAor)
                return aorMutations(*v).map!(a => cast(Mutation.Kind) a).array();
            else
                return null;
        };
        transf.assignOpOpCallback ~= (OpKind k) {
            if (auto v = k in isAorAssign)
                return aorAssignMutations(*v).map!(a => cast(Mutation.Kind) a).array();
            else
                return null;
        };

        transf.binaryOpOpCallback ~= (OpKind k) {
            if (k in isRor)
                return rorMutations(k).op.map!(a => cast(Mutation.Kind) a).array();
            else
                return null;
        };
        transf.binaryOpExprCallback ~= (OpKind k) {
            if (k in isRor)
                return [rorMutations(k).expr];
            else
                return null;
        };

        //transf.binaryOpLhsCallback ~= (OpKind k) => uoiLvalueMutations;
        //transf.binaryOpRhsCallback ~= (OpKind k) => uoiLvalueMutations;

        transf.binaryOpLhsCallback ~= (OpKind k) => [Mutation.Kind.corRhs];
        transf.binaryOpRhsCallback ~= (OpKind k) => [Mutation.Kind.corLhs];
        transf.binaryOpOpCallback ~= (OpKind k) {
            if (auto v = k in isCor)
                return corOpMutations(*v).map!(a => cast(Mutation.Kind) a).array();
            else
                return null;
        };
        transf.binaryOpExprCallback ~= (OpKind k) {
            if (auto v = k in isCor)
                return corExprMutations(*v).map!(a => cast(Mutation.Kind) a).array();
            else
                return null;
        };
    }

    const(MutationPointEntry[]) mutationPoints() {
        return result.mutationPoints;
    }

    Path[] mutationPointFiles() @trusted {
        return result.mutationPointFiles;
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
        transf.statement(v);
        v.accept(this);
    }

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());
        transf.unaryInject(v.cursor);
        v.accept(this);
    }

    override void visit(const IntegerLiteral v) {
        mixin(mixinNodeLog!());
        transf.unaryInject(v.cursor);
        v.accept(this);
    }

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());

        // #SPC-plugin_mutate_mutations_statement_del-call_expression
        transf.statement(v);

        transf.binaryOp(v.cursor);

        v.accept(this);
    }

    override void visit(const(BreakStmt) v) {
        mixin(mixinNodeLog!());
        transf.statement(v);
        v.accept(this);
    }

    override void visit(const(BinaryOperator) v) {
        mixin(mixinNodeLog!());
        transf.binaryOp(v.cursor);
        v.accept(this);
    }

    override void visit(const(CompoundAssignOperator) v) {
        mixin(mixinNodeLog!());
        transf.assignOp(v.cursor);
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
        transf.statement(v);
        v.accept(this);
    }
}

private:

/** Inject code to validate and check the location of a cursor.
 *
 * Params:
 *   cursor = code snippet to get the cursor from a variable accessable in the method.
 */
string makeAndCheckLocation(string cursor) {
    import std.format : format;

    return format(q{auto loc = %s.location;
    if (!val_loc.shouldAnalyze(loc.path)) {
        return;
    }}, cursor);
}

struct Transform {
    import std.algorithm : map;
    import std.array : array;
    import dextool.clang_extensions : OpKind;
    import dextool.plugin.mutate.backend.type : Offset;
    import dextool.plugin.mutate.backend.utility;

    AnalyzeResult result;
    ValidateLoc val_loc;

    /// Any statement
    alias StatementEvent = Mutation.Kind[]delegate();
    StatementEvent[] stmtCallback;

    /// Any statement that should have a unary operator inserted before/after
    alias UnaryInjectEvent = Mutation.Kind[]delegate(ValueKind);
    UnaryInjectEvent[] unaryInjectCallback;

    /// Any binary operator
    alias BinaryOpEvent = Mutation.Kind[]delegate(OpKind kind);
    BinaryOpEvent[] binaryOpOpCallback;
    BinaryOpEvent[] binaryOpLhsCallback;
    BinaryOpEvent[] binaryOpRhsCallback;
    BinaryOpEvent[] binaryOpExprCallback;

    /// Assignment operators
    alias AssignOpKindEvent = Mutation.Kind[]delegate(OpKind kind);
    alias AssignOpEvent = Mutation.Kind[]delegate();
    AssignOpKindEvent[] assignOpOpCallback;
    AssignOpEvent[] assignOpLhsCallback;
    AssignOpEvent[] assignOpRhsCallback;

    void statement(T)(const(T) v) {
        mixin(makeAndCheckLocation("v.cursor"));
        mixin(mixinPath);

        auto offs = calcOffset(v);
        Mutation[] m;
        foreach (cb; stmtCallback) {
            m ~= cb().map!(a => Mutation(a)).array();
        }

        result.put(MutationPointEntry(MutationPoint(offs, m), path,
                SourceLoc(loc.line, loc.column)));
    }

    void unaryInject(const(Cursor) c) {
        import dextool.clang_extensions : exprValueKind, getUnderlyingExprNode;

        // nodes from getOperator can be invalid.
        if (!c.isValid)
            return;

        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);

        const auto kind = exprValueKind(getUnderlyingExprNode(c));
        Mutation[] m;
        foreach (cb; unaryInjectCallback) {
            m ~= cb(kind).map!(a => Mutation(a)).array();
        }

        auto p2 = MutationPointEntry(MutationPoint(offs, m), path,
                SourceLoc(loc.line, loc.column));
        result.put(p2);
    }

    void binaryOp(const(Cursor) c) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto mp = getOperatorMP(c);
        if (!mp.isValid)
            return;

        foreach (cb; binaryOpOpCallback)
            mp.op.mp.mutations ~= cb(mp.rawOp.kind).map!(a => Mutation(a)).array();
        foreach (cb; binaryOpLhsCallback)
            mp.lhs.mp.mutations ~= cb(mp.rawOp.kind).map!(a => Mutation(a)).array();
        foreach (cb; binaryOpRhsCallback)
            mp.rhs.mp.mutations ~= cb(mp.rawOp.kind).map!(a => Mutation(a)).array();
        foreach (cb; binaryOpExprCallback)
            mp.expr.mp.mutations ~= cb(mp.rawOp.kind).map!(a => Mutation(a)).array();

        result.put(mp.lhs);
        result.put(mp.rhs);
        result.put(mp.op);
        result.put(mp.expr);
    }

    void assignOp(const Cursor c) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto mp = getOperatorMP(c);
        if (!mp.isValid)
            return;

        foreach (cb; assignOpOpCallback)
            mp.op.mp.mutations ~= cb(mp.rawOp.kind).map!(a => Mutation(a)).array();

        foreach (cb; assignOpLhsCallback)
            mp.lhs.mp.mutations ~= cb().map!(a => Mutation(a)).array();

        foreach (cb; assignOpRhsCallback)
            mp.lhs.mp.mutations ~= cb().map!(a => Mutation(a)).array();

        result.put(mp.lhs);
        result.put(mp.rhs);
        result.put(mp.op);
    }

    private static struct OperatorMP {
        bool isValid;
        Operator rawOp;
        /// the left side INCLUDING the operator
        MutationPointEntry lhs;
        /// the right side INCLUDING the operator
        MutationPointEntry rhs;
        /// the operator
        MutationPointEntry op;
        /// the whole operator expression
        MutationPointEntry expr;
    }

    OperatorMP getOperatorMP(const(Cursor) c) {
        import dextool.clang_extensions : getExprOperator;

        typeof(return) rval;

        auto op_ = getExprOperator(c);
        if (!op_.isValid)
            return rval;

        rval.rawOp = op_;

        SourceLocation loc = op_.cursor.location;

        auto path = loc.path.Path;
        if (path is null)
            return rval;
        result.put(path);

        rval.isValid = op_.isValid;

        // construct the mutations points to allow the delegates to fill with data
        auto sloc = SourceLoc(loc.line, loc.column);

        void sidesPoint() {
            auto opsr = op_.location.spelling;
            auto sr = op_.cursor.extent;

            auto offs_rhs = Offset(opsr.offset, sr.end.offset);
            rval.rhs = MutationPointEntry(MutationPoint(offs_rhs, null), path, sloc);

            auto offs_lhs = Offset(sr.start.offset, cast(uint)(opsr.offset + op_.length));
            rval.lhs = MutationPointEntry(MutationPoint(offs_lhs, null), path, sloc);
        }

        void opPoint() {
            auto sr = op_.location.spelling;
            auto offs = Offset(sr.offset, cast(uint)(sr.offset + op_.length));
            rval.op = MutationPointEntry(MutationPoint(offs, null), path, sloc);
        }

        void exprPoint() {
            // TODO this gives a slightly different result from calling getUnderlyingExprNode on v.cursor.
            // Investigate which one is the "correct" way.
            auto sr = op_.cursor.extent;
            auto offs_expr = Offset(sr.start.offset, sr.end.offset);
            rval.expr = MutationPointEntry(MutationPoint(offs_expr, null), path, sloc);
        }

        sidesPoint();
        opPoint();
        exprPoint();

        return rval;
    }

    // expects a makeAndCheckLocation exists before.
    private static string mixinPath() {
        // a bug in getExprOperator makes the path for a ++ which is overloaded
        // is null.
        return q{
            auto path = loc.path.Path;
            if (path is null)
                return;
            result.put(path);
        };
    }
}

import dextool.clang_extensions : Operator;

import clang.c.Index : CXTokenKind;
import dextool.plugin.mutate.backend.type : Offset;

class AnalyzeResult {
    import std.array : Appender;

    Appender!(MutationPointEntry[]) exprs;
    bool[Path] files;

    void put(MutationPointEntry a) {
        exprs.put(a);
    }

    void put(Path a) {
        files[a] = true;
    }

    const(MutationPointEntry[]) mutationPoints() {
        return exprs.data;
    }

    Path[] mutationPointFiles() @trusted {
        import std.array : array;

        return files.byKey.array();
    }
}

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
