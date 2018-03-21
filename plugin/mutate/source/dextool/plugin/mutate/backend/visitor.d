/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.visitor;

@safe:

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
import dextool.plugin.mutate.backend.type : MutationPoint, SourceLoc,
    OpTypeInfo;

/// Contain a visitor and the data.
struct VisitorResult {
    const(MutationPointEntry[]) mutationPoints() {
        return result.mutationPoints;
    }

    Path[] mutationPointFiles() @trusted {
        return result.mutationPointFiles;
    }

    ExtendedVisitor visitor;

private:
    ValidateLoc validateLoc;
    AnalyzeResult result;
    Transform transf;
    EnumCache enum_cache;
}

/** Construct and configure a visitor to analyze a clang AST for mutations.
 *
 * Params:
 *  val_loc_ = queried by the visitor with paths for the AST nodes to determine
 *      if they should be analyzed.
 */
VisitorResult makeRootVisitor(ValidateLoc val_loc_) {
    typeof(return) rval;
    rval.validateLoc = val_loc_;
    rval.result = new AnalyzeResult;
    rval.transf = new Transform(rval.result, val_loc_);
    rval.enum_cache = new EnumCache;
    rval.visitor = new BaseVisitor(rval.transf, rval.enum_cache);

    import dextool.clang_extensions : OpKind;
    import dextool.plugin.mutate.backend.utility : stmtDelMutations,
        absMutations, uoiLvalueMutations, uoiRvalueMutations, isDcc,
        dccBranchMutations, dccCaseMutations, dcrCaseMutations;

    //rval.transf.stmtCallback ~= () => stmtDelMutations;
    rval.transf.funcCallCallback ~= () => stmtDelMutations;

    rval.transf.unaryInjectCallback ~= (ValueKind k) => absMutations;
    rval.transf.binaryOpExprCallback ~= (OpKind k) => absMutations;

    rval.transf.unaryInjectCallback ~= (ValueKind k) => k == ValueKind.lvalue
        ? uoiLvalueMutations : uoiRvalueMutations;

    rval.transf.branchCondCallback ~= () => dccBranchMutations;
    rval.transf.binaryOpExprCallback ~= (OpKind k) {
        return k in isDcc ? dccBranchMutations : null;
    };

    rval.transf.caseSubStmtCallback ~= () => dccCaseMutations;
    rval.transf.caseStmtCallback ~= () => dcrCaseMutations;

    import std.algorithm : map;
    import std.array : array;
    import dextool.plugin.mutate.backend.type : Mutation;
    import dextool.plugin.mutate.backend.utility : isLcr, lcrMutations, isAor,
        aorMutations, isAorAssign, aorAssignMutations, isRor, rorMutations,
        isCor, corOpMutations, corExprMutations;

    // TODO refactor so array() can be removed. It is an unnecessary allocation
    rval.transf.binaryOpOpCallback ~= (OpKind k, OpTypeInfo) {
        if (auto v = k in isLcr)
            return lcrMutations(*v).map!(a => cast(Mutation.Kind) a).array();
        else
            return null;
    };

    rval.transf.binaryOpOpCallback ~= (OpKind k, OpTypeInfo) {
        if (auto v = k in isAor)
            return aorMutations(*v).map!(a => cast(Mutation.Kind) a).array();
        else
            return null;
    };
    rval.transf.assignOpOpCallback ~= (OpKind k) {
        if (auto v = k in isAorAssign)
            return aorAssignMutations(*v).map!(a => cast(Mutation.Kind) a).array();
        else
            return null;
    };

    rval.transf.binaryOpOpCallback ~= (OpKind k, OpTypeInfo tyi) {
        if (k in isRor)
            return rorMutations(k, tyi).op.map!(a => cast(Mutation.Kind) a).array();
        else
            return null;
    };
    rval.transf.binaryOpExprCallback ~= (OpKind k) {
        if (k in isRor)
            return rorMutations(k, OpTypeInfo.none).expr;
        else
            return null;
    };

    //rval.transf.binaryOpLhsCallback ~= (OpKind k) => uoiLvalueMutations;
    //rval.transf.binaryOpRhsCallback ~= (OpKind k) => uoiLvalueMutations;

    rval.transf.binaryOpLhsCallback ~= (OpKind k, OpTypeInfo) => k in isCor
        ? [Mutation.Kind.corRhs] : null;
    rval.transf.binaryOpRhsCallback ~= (OpKind k, OpTypeInfo) => k in isCor
        ? [Mutation.Kind.corLhs] : null;
    rval.transf.binaryOpOpCallback ~= (OpKind k, OpTypeInfo) {
        if (auto v = k in isCor)
            return corOpMutations(*v).map!(a => cast(Mutation.Kind) a).array();
        else
            return null;
    };
    rval.transf.binaryOpExprCallback ~= (OpKind k) {
        if (auto v = k in isCor)
            return corExprMutations(*v).map!(a => cast(Mutation.Kind) a).array();
        else
            return null;
    };

    return rval;
}

private:

/** Find all mutation points that affect a whole expression.
 *
 * TODO change the name of the class. It is more than just an expression
 * visitor.
 *
 * # Usage of kind_stack
 * All usage of the kind_stack shall be documented here.
 *  - track assignments to avoid generating unary insert operators for the LHS.
 */
class BaseVisitor : ExtendedVisitor {
    import clang.c.Index : CXCursorKind;
    import cpptooling.analyzer.clang.ast;
    import dextool.clang_extensions : getExprOperator, OpKind;

    alias visit = ExtendedVisitor.visit;

    mixin generateIndentIncrDecr;

    private Transform transf;
    private EnumCache enum_cache;

    /// Track the visited nodes
    private Stack!CXCursorKind kind_stack;

    /**
     * Params:
     *  restrict = only analyze files starting with this path
     */
    this(Transform transf, EnumCache ec, const uint indent = 0) nothrow {
        this.transf = transf;
        this.indent = indent;
        this.enum_cache = ec;
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

    override void visit(const EnumDecl v) @trusted {
        mixin(mixinNodeLog!());
        import std.typecons : scoped;

        auto vis = scoped!EnumVisitor(indent);
        v.accept(vis);

        if (!vis.entry.isNull) {
            enum_cache.put(EnumCache.USR(v.cursor.usr), vis.entry);
        }

        debug logger.tracef("%s", enum_cache);
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

        if (kind_stack.hasValue(CXCursorKind.compoundAssignOperator).isNull)
            transf.unaryInject(v.cursor);
        v.accept(this);
    }

    override void visit(const IntegerLiteral v) {
        mixin(mixinNodeLog!());
        //transf.unaryInject(v.cursor);
        v.accept(this);
    }

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());
        transf.binaryOp(v.cursor, enum_cache);
        transf.funcCall(v.cursor);
        v.accept(this);
    }

    override void visit(const(BreakStmt) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(BinaryOperator) v) {
        mixin(mixinNodeLog!());
        transf.binaryOp(v.cursor, enum_cache);
        v.accept(this);
    }

    override void visit(const(CompoundAssignOperator) v) {
        mixin(mixinNodeLog!());
        mixin(pushPopStack("kind_stack", "v.cursor.kind"));
        transf.assignOp(v.cursor, enum_cache);
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

    // trusted: the scope allocated visitor do not escape the method
    override void visit(const IfStmt v) @trusted {
        mixin(mixinNodeLog!());
        import std.typecons : scoped;

        auto clause = scoped!IfStmtClauseVisitor(transf, enum_cache, indent);
        auto ifstmt = scoped!IfStmtVisitor(transf, enum_cache, this, clause, indent);
        accept(v, cast(IfStmtVisitor) ifstmt);
    }

    override void visit(const CaseStmt v) {
        mixin(mixinNodeLog!());
        transf.caseStmt(v.cursor);
        v.accept(this);
    }
}

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

struct Stack(T) {
    import std.typecons : Nullable;
    import std.container : Array;

    Array!T arr;

    // trusted: as long as arr do not escape the instance
    void put(T a) @trusted {
        arr.insertBack(a);
    }

    // trusted: as long as arr do not escape the instance
    void pop() @trusted {
        arr.removeBack;
    }

    /** Check from the top of the stack if v is in the stack
     *
     * trusted: the slice never escape the method and v never affects the
     * slicing thus the memory.
     */
    Nullable!size_t hasValue(T v) @trusted {
        import std.range : retro, enumerate;

        foreach (idx, a; arr[].retro.enumerate) {
            if (a == v)
                return typeof(return)(idx);
        }

        return typeof(return)();
    }
}

/// A mixin string that pushes `value` to `instance` and pops on scope exit.
string pushPopStack(string instance, string value) {
    import std.format : format;

    return format(q{%s.put(%s); scope(exit) %s.pop;}, instance, value, instance);
}

/** Transform the AST to mutation poins and mutations.
 *
 * The intent is to decouple the AST visitor from the transformation logic.
 *
 * TODO reduce code duplication. Do it after the first batch of mutations are
 * implemented.
 */
class Transform {
    import std.algorithm : map;
    import std.array : array;
    import dextool.clang_extensions : OpKind;
    import dextool.plugin.mutate.backend.type : Offset;
    import dextool.plugin.mutate.backend.utility;

    /// Any statement
    alias StatementEvent = Mutation.Kind[]delegate();
    alias FunctionCallEvent = Mutation.Kind[]delegate();
    StatementEvent[] stmtCallback;
    FunctionCallEvent[] funcCallCallback;

    /// Any statement that should have a unary operator inserted before/after
    alias UnaryInjectEvent = Mutation.Kind[]delegate(ValueKind);
    UnaryInjectEvent[] unaryInjectCallback;

    /// Any binary operator
    alias BinaryOpEvent = Mutation.Kind[]delegate(OpKind kind, OpTypeInfo tyi);
    alias BinaryExprEvent = Mutation.Kind[]delegate(OpKind kind);
    BinaryOpEvent[] binaryOpOpCallback;
    BinaryOpEvent[] binaryOpLhsCallback;
    BinaryOpEvent[] binaryOpRhsCallback;
    BinaryExprEvent[] binaryOpExprCallback;

    /// Assignment operators
    alias AssignOpKindEvent = Mutation.Kind[]delegate(OpKind kind);
    alias AssignOpEvent = Mutation.Kind[]delegate();
    AssignOpKindEvent[] assignOpOpCallback;
    AssignOpEvent[] assignOpLhsCallback;
    AssignOpEvent[] assignOpRhsCallback;

    /// Branch condition expression such as those in an if stmt
    alias BranchEvent = Mutation.Kind[]delegate();
    BranchEvent[] branchCondCallback;
    BranchEvent[] branchClauseCallback;
    BranchEvent[] branchThenCallback;
    BranchEvent[] branchElseCallback;

    /// Switch condition
    alias CaseEvent = Mutation.Kind[]delegate();
    /// the statement after the `case 2:` until the next one
    CaseEvent[] caseStmtCallback;
    CaseEvent[] caseSubStmtCallback;

    private AnalyzeResult result;
    private ValidateLoc val_loc;

    this(AnalyzeResult res, ValidateLoc vloc) {
        this.result = res;
        this.val_loc = vloc;
    }

    private void noArgCallback(T)(const Cursor c, T callbacks) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);

        auto p = MutationPointEntry(MutationPoint(offs), path, SourceLoc(loc.line, loc.column));
        foreach (cb; callbacks) {
            p.mp.mutations ~= cb().map!(a => Mutation(a)).array();
        }

        result.put(p);
    }

    void statement(T)(const(T) v) {
        mixin(makeAndCheckLocation("v.cursor"));
        mixin(mixinPath);

        auto offs = calcOffset(v);
        auto p = MutationPointEntry(MutationPoint(offs), path, SourceLoc(loc.line, loc.column));
        foreach (cb; stmtCallback) {
            p.mp.mutations ~= cb().map!(a => Mutation(a)).array();
        }

        result.put(p);
    }

    void funcCall(const Cursor c) {
        noArgCallback(c, funcCallCallback);
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

        auto p = MutationPointEntry(MutationPoint(offs, null), path,
                SourceLoc(loc.line, loc.column));
        foreach (cb; unaryInjectCallback) {
            p.mp.mutations ~= cb(kind).map!(a => Mutation(a)).array();
        }

        result.put(p);
    }

    void binaryOp(const(Cursor) c, const EnumCache ec) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto mp = getOperatorMP(c, ec);
        if (!mp.isValid)
            return;

        binaryOpInternal(mp);

        result.put(mp.lhs);
        result.put(mp.rhs);
        result.put(mp.op);
        result.put(mp.expr);
    }

    private void binaryOpInternal(ref OperatorMP mp) {
        foreach (cb; binaryOpOpCallback)
            mp.op.mp.mutations ~= cb(mp.rawOp.kind, mp.typeInfo).map!(a => Mutation(a)).array();
        foreach (cb; binaryOpLhsCallback)
            mp.lhs.mp.mutations ~= cb(mp.rawOp.kind, mp.typeInfo).map!(a => Mutation(a)).array();
        foreach (cb; binaryOpRhsCallback)
            mp.rhs.mp.mutations ~= cb(mp.rawOp.kind, mp.typeInfo).map!(a => Mutation(a)).array();
        foreach (cb; binaryOpExprCallback)
            mp.expr.mp.mutations ~= cb(mp.rawOp.kind).map!(a => Mutation(a)).array();
    }

    void assignOp(const Cursor c, const EnumCache ec) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto mp = getOperatorMP(c, ec);
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

    /** Callback for the whole condition in a if statement.
     */
    void branchCond(const Cursor c, const EnumCache ec) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto mp = getOperatorMP(c, ec);
        if (mp.isValid) {
            binaryOpInternal(mp);

            foreach (cb; branchClauseCallback) {
                mp.expr.mp.mutations ~= cb().map!(a => Mutation(a)).array();
            }

            result.put(mp.lhs);
            result.put(mp.rhs);
            result.put(mp.op);
            result.put(mp.expr);
        } else {
            auto sr = c.extent;
            auto offs = Offset(sr.start.offset, sr.end.offset);
            auto p = MutationPointEntry(MutationPoint(offs, null), path,
                    SourceLoc(loc.line, loc.column));

            foreach (cb; branchCondCallback) {
                p.mp.mutations ~= cb().map!(a => Mutation(a)).array();
            }

            result.put(p);
        }
    }

    /** Callback for the individual clauses in an if statement.
     */
    void branchClause(const Cursor c, const EnumCache ec) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto mp = getOperatorMP(c, ec);
        if (!mp.isValid)
            return;

        binaryOpInternal(mp);

        foreach (cb; branchClauseCallback) {
            mp.expr.mp.mutations ~= cb().map!(a => Mutation(a)).array();
        }

        result.put(mp.lhs);
        result.put(mp.rhs);
        result.put(mp.op);
        result.put(mp.expr);
    }

    void branchThen(const Cursor c) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);

        auto p = MutationPointEntry(MutationPoint(offs, null), path,
                SourceLoc(loc.line, loc.column));

        foreach (cb; branchThenCallback) {
            p.mp.mutations ~= cb().map!(a => Mutation(a)).array();
        }

        result.put(p);
    }

    void branchElse(const Cursor c) {
        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);

        auto p = MutationPointEntry(MutationPoint(offs, null), path,
                SourceLoc(loc.line, loc.column));

        foreach (cb; branchElseCallback) {
            p.mp.mutations ~= cb().map!(a => Mutation(a)).array();
        }

        result.put(p);
    }

    void caseStmt(const Cursor c) {
        import clang.c.Index : CXTokenKind, CXCursorKind;
        import dextool.clang_extensions : getCaseStmt;

        auto mp = getCaseStmt(c);
        if (!mp.isValid)
            return;

        mixin(makeAndCheckLocation("c"));
        mixin(mixinPath);

        auto sr = mp.subStmt.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);
        if (mp.subStmt.kind == CXCursorKind.caseStmt) {
            // a case statement with fallthrough. the only point to inject a bomb is directly efter the semicolon
            offs.begin = mp.colonLocation.offset + 1;
            offs.end = offs.begin;
        } else if (mp.subStmt.kind != CXCursorKind.compoundStmt) {
            offs.end = findTokenOffset(c.translationUnit.cursor.tokens, offs,
                    CXTokenKind.punctuation);
        }

        void subStmt() {
            auto p = MutationPointEntry(MutationPoint(offs), path,
                    SourceLoc(loc.line, loc.column));

            foreach (cb; caseSubStmtCallback) {
                p.mp.mutations ~= cb().map!(a => Mutation(a)).array();
            }

            result.put(p);
        }

        void stmt() {
            auto stmt_sr = c.extent;
            // reuse the end from offs because it also covers either only the fallthrough OR also the end semicolon
            auto stmt_offs = Offset(stmt_sr.start.offset, offs.end);

            auto p = MutationPointEntry(MutationPoint(stmt_offs), path,
                    SourceLoc(loc.line, loc.column));

            foreach (cb; caseStmtCallback) {
                p.mp.mutations ~= cb().map!(a => Mutation(a)).array();
            }

            result.put(p);
        }

        stmt();
        subStmt();
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
        /// Type information of the types on the sides of the operator
        OpTypeInfo typeInfo;
    }

    OperatorMP getOperatorMP(const(Cursor) c, const EnumCache ec) {
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

        void sidesPoint() {
            auto sides = op_.sides;
            auto opsr = op_.location.spelling;
            auto sr = op_.cursor.extent;

            if (sides.rhs.isValid) {
                auto offs_rhs = Offset(opsr.offset, sr.end.offset);
                rval.rhs = MutationPointEntry(MutationPoint(offs_rhs, null), path,
                        SourceLoc(sides.rhs.location.line, sides.rhs.location.column));
            }

            if (sides.lhs.isValid) {
                auto offs_lhs = Offset(sr.start.offset, cast(uint)(opsr.offset + op_.length));
                rval.lhs = MutationPointEntry(MutationPoint(offs_lhs, null), path,
                        SourceLoc(sides.lhs.location.line, sides.lhs.location.column));
            }
        }

        void opPoint() {
            auto sr = op_.location.spelling;
            auto offs = Offset(sr.offset, cast(uint)(sr.offset + op_.length));
            rval.op = MutationPointEntry(MutationPoint(offs, null), path,
                    SourceLoc(op_.location.line, op_.location.column));

            auto sides = op_.sides;
            rval.typeInfo = deriveOpTypeInfo(sides.lhs, sides.rhs, ec);
        }

        void exprPoint() {
            auto sloc = SourceLoc(loc.line, loc.column);

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

OpTypeInfo deriveOpTypeInfo(const Cursor lhs_, const Cursor rhs_, const EnumCache ec) @safe {
    import std.meta : AliasSeq;
    import std.algorithm : among;
    import clang.c.Index : CXTypeKind, CXCursorKind;
    import clang.Type : Type;
    import dextool.clang_extensions : getUnderlyingExprNode;

    auto lhs = Cursor(getUnderlyingExprNode(lhs_));
    auto rhs = Cursor(getUnderlyingExprNode(rhs_));

    if (!lhs.isValid || !rhs.isValid)
        return OpTypeInfo.none;

    auto lhs_ty = lhs.type.canonicalType;
    auto rhs_ty = rhs.type.canonicalType;

    if (!lhs_ty.isValid || !rhs_ty.isValid)
        return OpTypeInfo.none;

    auto floatCategory = AliasSeq!(CXTypeKind.float_, CXTypeKind.double_, CXTypeKind.longDouble);
    auto pointerCategory = AliasSeq!(CXTypeKind.nullPtr, CXTypeKind.pointer,
            CXTypeKind.blockPointer, CXTypeKind.memberPointer);
    auto boolCategory = AliasSeq!(CXTypeKind.bool_);

    if (lhs_ty.isEnum && rhs_ty.isEnum) {
        auto lhs_ref = lhs.referenced;
        auto rhs_ref = rhs.referenced;
        if (!lhs_ref.isValid || !rhs_ref.isValid)
            return OpTypeInfo.none;

        auto lhs_usr = lhs_ref.usr;
        auto rhs_usr = rhs_ref.usr;

        debug logger.tracef("lhs:%s:%s rhs:%s:%s", lhs_usr, lhs_ref.kind, rhs_usr, rhs_ref.kind);

        if (lhs_usr == rhs_usr) {
            return OpTypeInfo.enumLhsRhsIsSame;
        } else if (lhs_ref.kind == CXCursorKind.enumConstantDecl) {
            auto lhs_ty_decl = lhs_ty.declaration;
            if (!lhs_ty_decl.isValid)
                return OpTypeInfo.none;

            auto p = ec.position(EnumCache.USR(lhs_ty_decl.usr), EnumCache.USR(lhs_usr));
            if (p == EnumCache.Query.isMin)
                return OpTypeInfo.enumLhsIsMin;
            else if (p == EnumCache.Query.isMax)
                return OpTypeInfo.enumLhsIsMax;
            return OpTypeInfo.none;
        } else if (rhs_ref.kind == CXCursorKind.enumConstantDecl) {
            auto rhs_ty_decl = rhs_ty.declaration;
            if (!rhs_ty_decl.isValid)
                return OpTypeInfo.none;

            auto p = ec.position(EnumCache.USR(rhs_ty_decl.usr), EnumCache.USR(rhs_usr));
            if (p == EnumCache.Query.isMin)
                return OpTypeInfo.enumRhsIsMin;
            else if (p == EnumCache.Query.isMax)
                return OpTypeInfo.enumRhsIsMax;
            return OpTypeInfo.none;
        }

        return OpTypeInfo.none;
    } else if (lhs_ty.kind.among(floatCategory) && rhs_ty.kind.among(floatCategory)) {
        return OpTypeInfo.floatingPoint;
    } else if (lhs_ty.kind.among(pointerCategory) || rhs_ty.kind.among(pointerCategory)) {
        return OpTypeInfo.pointer;
    } else if (lhs_ty.kind.among(boolCategory) && rhs_ty.kind.among(boolCategory)) {
        return OpTypeInfo.boolean;
    }

    return OpTypeInfo.none;
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

        // TODO inactivated because it leaks memory. Unable to run on sqlite3.

        // TODO this is extremly inefficient. change to a more localized cursor
        // or even better. Get the tokens at the end.
        //auto arg = v.cursor.translationUnit.cursor;
        //
        //rval.end = findTokenOffset(arg.tokens, rval, CXTokenKind.punctuation, ";");
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

/// trusted: trusting the impl in clang.
uint findTokenOffset(T)(T toks, Offset sr, CXTokenKind kind) @trusted {
    foreach (ref t; toks) {
        if (t.location.offset >= sr.end) {
            if (t.kind == kind) {
                return t.extent.end.offset;
            }
            break;
        }
    }

    return sr.end;
}

final class IfStmtVisitor : ExtendedVisitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = ExtendedVisitor.visit;

    mixin generateIndentIncrDecr;

    private {
        Transform transf;
        EnumCache enum_cache;
        ExtendedVisitor sub_visitor;
        ExtendedVisitor cond_visitor;
    }

    /**
     * Params:
     *  sub_visitor = visitor used for recursive analyze.
     */
    this(Transform transf, EnumCache ec, ExtendedVisitor sub_visitor,
            ExtendedVisitor cond_visitor, const uint indent) {
        this.transf = transf;
        this.enum_cache = ec;
        this.sub_visitor = sub_visitor;
        this.cond_visitor = cond_visitor;
        this.indent = indent;
    }

    override void visit(const IfStmtCond v) {
        mixin(mixinNodeLog!());
        transf.branchCond(v.cursor, enum_cache);
        v.accept(cond_visitor);
    }

    override void visit(const IfStmtThen v) {
        mixin(mixinNodeLog!());
        transf.branchThen(v.cursor);
        v.accept(sub_visitor);
    }

    override void visit(const IfStmtElse v) {
        mixin(mixinNodeLog!());
        transf.branchElse(v.cursor);
        v.accept(sub_visitor);
    }
}

/// Visit all clauses in the condition of a statement.
final class IfStmtClauseVisitor : BaseVisitor {
    import cpptooling.analyzer.clang.ast;

    alias visit = BaseVisitor.visit;

    /**
     * Params:
     *  transf = ?
     *  sub_visitor = visitor used for recursive analyze.
     */
    this(Transform transf, EnumCache ec, const uint indent) {
        super(transf, ec, indent);
    }

    override void visit(const(BinaryOperator) v) {
        mixin(mixinNodeLog!());
        transf.branchClause(v.cursor, enum_cache);
        v.accept(this);
    }
}

/// Cache enums that are found in the AST for later lookup
class EnumCache {
    static struct USR {
        string payload;
        alias payload this;
    }

    static struct Entry {
        long minValue;
        USR[] minId;

        long maxValue;
        USR[] maxId;
    }

    enum Query {
        unknown,
        isMin,
        isMiddle,
        isMax,
    }

    Entry[USR] cache;

    void put(USR u, Entry e) {
        cache[u] = e;
    }

    /// Check what position the enum const declaration have in enum declaration.
    Query position(USR enum_, USR enum_const_decl) const {
        import std.algorithm : canFind;

        if (auto v = enum_ in cache) {
            if ((*v).minId.canFind(enum_const_decl))
                return Query.isMin;
            else if ((*v).maxId.canFind(enum_const_decl))
                return Query.isMax;
            return Query.isMiddle;
        }

        return Query.unknown;
    }

    import std.format : FormatSpec;

    // trusted: remove when upgrading to dmd-FE 2.078.1
    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) @trusted const {
        import std.format : formatValue, formattedWrite;
        import std.range.primitives : put;

        foreach (kv; cache.byKeyValue) {
            formattedWrite(w, "enum:%s min:%s:%s max:%s:%s", kv.key,
                    kv.value.minValue, kv.value.minId, kv.value.maxValue, kv.value.maxId);
        }
    }

    // remove this function when upgrading to dmd-FE 2.078.1
    override string toString() @trusted pure const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
}

final class EnumVisitor : Visitor {
    import std.typecons : Nullable;
    import cpptooling.analyzer.clang.ast;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    Nullable!(EnumCache.Entry) entry;

    this(const uint indent) {
        this.indent = indent;
    }

    override void visit(const EnumDecl v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const EnumConstantDecl v) @trusted {
        mixin(mixinNodeLog!());

        Cursor c = v.cursor;
        long value = c.enum_.signedValue;

        if (entry.isNull) {
            entry = EnumCache.Entry(value, [EnumCache.USR(c.usr)], value, [EnumCache.USR(c.usr)]);
        } else if (value < entry.minValue) {
            entry.minValue = value;
            entry.minId = [EnumCache.USR(c.usr)];
        } else if (value == entry.minValue) {
            entry.minId ~= EnumCache.USR(c.usr);
        } else if (value > entry.maxValue) {
            entry.maxValue = value;
            entry.maxId = [EnumCache.USR(c.usr)];
        } else if (value == entry.maxValue) {
            entry.maxId ~= EnumCache.USR(c.usr);
        }

        v.accept(this);
    }
}

// Intende to move this code to clang_extensions if this approach to extending the clang AST works well.
// --- BEGIN

static import dextool.clang_extensions;

static import cpptooling.analyzer.clang.ast;

class ExtendedVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import dextool.clang_extensions;

    alias visit = Visitor.visit;

    void visit(const(IfStmtInit) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(IfStmtCond) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(IfStmtThen) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(IfStmtElse) value) {
        visit(cast(const(Statement)) value);
    }
}

final class IfStmtInit : cpptooling.analyzer.clang.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class IfStmtCond : cpptooling.analyzer.clang.ast.Expression {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class IfStmtThen : cpptooling.analyzer.clang.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class IfStmtElse : cpptooling.analyzer.clang.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

void accept(T)(const(cpptooling.analyzer.clang.ast.IfStmt) n, T v)
        if (is(T : ExtendedVisitor)) {
    import dextool.clang_extensions;

    auto stmt = getIfStmt(n.cursor);
    accept(stmt, v);
}

void accept(T)(ref dextool.clang_extensions.IfStmt n, T v)
        if (is(T : ExtendedVisitor)) {
    import std.traits : hasMember;

    static if (hasMember!(T, "incr"))
        v.incr;
    {
        if (n.init_.isValid) {
            auto sub = new IfStmtInit(n.init_);
            v.visit(sub);
        }
    }
    {
        if (n.cond.isValid) {
            auto sub = new IfStmtCond(n.cond);
            v.visit(sub);
        }
    }
    {
        if (n.then.isValid) {
            auto sub = new IfStmtThen(n.then);
            v.visit(sub);
        }
    }
    {
        if (n.else_.isValid) {
            auto sub = new IfStmtElse(n.else_);
            v.visit(sub);
        }
    }

    static if (hasMember!(T, "decr"))
        v.decr;
}

// --- END
