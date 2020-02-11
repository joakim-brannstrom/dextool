/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.schemata;

import logger = std.experimental.logger;
import std.algorithm : among, map, sort, filter;
import std.array : appender, empty, array, Appender;
import std.exception : collectException;
import std.format : formattedWrite;
import std.meta : AliasSeq;
import std.range : retro, ElementType;
import std.typecons : Nullable, tuple, Tuple, scoped;

import automem : vector, Vector;

import clang.Cursor : Cursor;
import clang.Eval : Eval;
import clang.Type : Type;
import clang.c.Index : CXTypeKind, CXCursorKind, CXEvalResultKind, CXTokenKind;

import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

import dextool.clang_extensions : getUnderlyingExprNode;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast : Interval, Location;
import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.internal;
import dextool.plugin.mutate.backend.database : MutationPointEntry, MutationPointEntry2;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset, Mutation, SourceLocRange;

import analyze = dextool.plugin.mutate.backend.analyze.ast;

alias accept = dextool.plugin.mutate.backend.analyze.extensions.accept;

/** Translate a clang AST to a mutation AST.
 */
analyze.Ast toMutateAst(const Cursor root) @trusted {
    import cpptooling.analyzer.clang.ast : ClangAST;

    auto svisitor = scoped!BaseVisitor();
    auto visitor = cast(BaseVisitor) svisitor;
    auto ast = ClangAST!BaseVisitor(root);
    ast.accept(visitor);
    return visitor.ast;
}

@safe:

/// Find mutants.
MutantsResult toMutants(ref analyze.Ast ast, FilesysIO fio, ValidateLoc vloc) {
    auto visitor = () @trusted { return new MutantVisitor(&ast, fio, vloc); }();
    ast.accept(visitor);
    return visitor.result;
}

/// Filter the mutants and add checksums.
CodeMutantsResult toCodeMutants(MutantsResult mutants, FilesysIO fio, TokenStream tstream) {
    auto result = new CodeMutantsResult(mutants.lang, fio, tstream);
    result.put(mutants.files);

    foreach (f; mutants.files.map!(a => a.path)) {
        foreach (mp; mutants.getMutationPoints(f).array.sort!((a,
                b) => a.point.offset < b.point.offset)) {
            result.put(f, mp.point.offset, mp.point.sloc, mp.kind);
        }
    }

    return result;
}

/// Translate a mutation AST to a schemata.
void toSchemata(ref analyze.Ast ast) @safe {
    auto visitor = () @trusted { return new SchemataVisitor(&ast); }();
    ast.accept(visitor);
}

class MutantsResult {
    import dextool.plugin.mutate.backend.type : Checksum;
    import dextool.set;

    static struct MutationPoint {
        Offset offset;
        SourceLocRange sloc;

        size_t toHash() @safe pure nothrow const @nogc {
            return offset.toHash;
        }

        int opCmp(ref const typeof(this) rhs) @safe pure nothrow const @nogc {
            return offset.opCmp(rhs.offset);
        }

        string toString() @safe pure const {
            auto buf = appender!string;
            toString(buf);
            return buf.data;
        }

        void toString(Writer)(ref Writer w) const {
            formattedWrite!"[%s:%s-%s:%s]:[%s:%s]"(w, sloc.begin.line,
                    sloc.begin.column, sloc.end.line, sloc.end.column, offset.begin, offset.end);
        }
    }

    const Language lang;
    Tuple!(AbsolutePath, "path", Checksum, "cs")[] files;

    private {
        Set!(Mutation.Kind)[MutationPoint][AbsolutePath] points;
        Set!AbsolutePath existingFiles;
        FilesysIO fio;
        ValidateLoc vloc;
    }

    this(const Language lang, FilesysIO fio, ValidateLoc vloc) {
        this.lang = lang;
        this.fio = fio;
        this.vloc = vloc;
    }

    Tuple!(Mutation.Kind[], "kind", MutationPoint, "point")[] getMutationPoints(AbsolutePath file) @safe pure nothrow const {
        alias RType = ElementType!(typeof(return));
        return points[file].byKeyValue.map!(a => RType(a.value.toArray, a.key)).array;
    }

    private void put(Path raw) @trusted {
        import std.stdio : File;
        import dextool.plugin.mutate.backend.utility : checksum;

        auto absp = fio.toAbsoluteRoot(raw);

        if (!vloc.shouldMutate(absp) || absp in existingFiles)
            return;

        try {
            auto content = appender!(const(ubyte)[])();
            foreach (ubyte[] buf; File(absp).byChunk(4096)) {
                content.put(buf);
            }
            auto cs = checksum(content.data);

            existingFiles.add(absp);
            files ~= ElementType!(typeof(files))(absp, cs);
            points[absp] = (Set!(Mutation.Kind)[MutationPoint]).init;
        } catch (Exception e) {
            logger.warningf("%s: %s", absp, e.msg);
        }
    }

    private void put(Path raw, MutationPoint mp, Mutation.Kind kind) @safe {
        auto p = fio.toAbsoluteRoot(raw);

        if (auto a = p in points) {
            if (auto b = mp in *a) {
                (*b).add(kind);
            } else {
                Set!(Mutation.Kind) s;
                s.add(kind);
                (*a)[mp] = s;
            }
        }
    }

    override string toString() @safe {
        import std.range : put;

        auto w = appender!string();

        formattedWrite(w, "Files:\n");
        foreach (f; files) {
            formattedWrite!"%s %s\n"(w, f.path, f.cs);

            foreach (mp; points[f.path].byKeyValue
                    .map!(a => tuple!("key", "value")(a.key, a.value))
                    .array
                    .sort!((a, b) => a.key < b.key)) {
                formattedWrite(w, "  %s->%s\n", mp.key, mp.value.toRange);
            }
        }

        return w.data;
    }
}

/**
 * The design of the API have some calling requirements that do not make it
 * suitable for general consumtion. It is deemed OK as long as those methods
 * are private and used in only one place.
 */
class CodeMutantsResult {
    import dextool.hash : Checksum128, BuildChecksum128, toBytes, toChecksum128;
    import dextool.plugin.mutate.backend.type : CodeMutant, CodeChecksum, Mutation, Checksum;
    import dextool.plugin.mutate.backend.analyze.id_factory : MutationIdFactory;

    const Language lang;
    Tuple!(AbsolutePath, "path", Checksum, "cs")[] files;

    static struct MutationPoint {
        CodeMutant[] mutants;
        Offset offset;
        SourceLocRange sloc;

        size_t toHash() @safe pure nothrow const @nogc {
            return offset.toHash;
        }

        int opCmp(ref const typeof(this) rhs) @safe pure nothrow const @nogc {
            return offset.opCmp(rhs.offset);
        }

        string toString() @safe pure const {
            auto buf = appender!string;
            toString(buf);
            return buf.data;
        }

        void toString(Writer)(ref Writer w) const {
            formattedWrite!"[%s:%s-%s:%s]:[%s:%s]"(w, sloc.begin.line,
                    sloc.begin.column, sloc.end.line, sloc.end.column, offset.begin, offset.end);
        }
    }

    MutationPoint[][AbsolutePath] points;
    Checksum[AbsolutePath] csFiles;

    private {
        FilesysIO fio;

        TokenStream tstream;

        MutationIdFactory idFactory;
        /// Tokens of the current file that idFactory is configured for.
        Token[] tokens;
    }

    this(Language lang, FilesysIO fio, TokenStream tstream) {
        this.lang = lang;
        this.fio = fio;
        this.tstream = tstream;
    }

    private void put(typeof(MutantsResult.files) mfiles) {
        files = mfiles;
        foreach (f; files) {
            csFiles[f.path] = f.cs;
            points[f.path] = (MutationPoint[]).init;
        }
    }

    /// Returns: a tuple of two elements. The tokens before and after the mutation point.
    private static auto splitByMutationPoint(Token[] toks, Offset offset) {
        import std.algorithm : countUntil;
        import std.typecons : Tuple;

        Tuple!(size_t, "pre", size_t, "post") rval;

        const pre_idx = toks.countUntil!((a, b) => a.offset.begin > b.begin)(offset);
        if (pre_idx == -1) {
            rval.pre = toks.length;
            return rval;
        }

        rval.pre = pre_idx;
        toks = toks[pre_idx .. $];

        const post_idx = toks.countUntil!((a, b) => a.offset.end > b.end)(offset);
        if (post_idx != -1) {
            rval.post = toks.length - post_idx;
        }

        return rval;
    }

    // the mutation points must be added in sorted order by their offset
    private void put(AbsolutePath p, Offset offset, SourceLocRange sloc, Mutation.Kind[] kinds) @safe {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

        if (p != idFactory.fileName) {
            tokens = tstream.getFilteredTokens(p);
            idFactory = MutationIdFactory(p, csFiles[p], tokens);
        }

        auto split = splitByMutationPoint(tokens, offset);

        idFactory.updatePosition(split.pre, split.post);

        auto fin = fio.makeInput(p);
        auto cmuts = appender!(CodeMutant[])();
        foreach (kind; kinds) {
            auto txt = makeMutationText(fin, offset, kind, lang);
            auto cm = idFactory.makeMutant(Mutation(kind), txt.rawMutation);
            cmuts.put(cm);
        }

        points[p] ~= MutationPoint(cmuts.data, offset, sloc);
    }

    override string toString() @safe {
        import std.range : put;

        auto w = appender!string();

        formattedWrite(w, "Files:\n");
        foreach (f; files) {
            formattedWrite!"%s %s\n"(w, f.path, f.cs);

            foreach (mp; points[f.path]) {
                formattedWrite!"  %s->%s\n"(w, mp, mp.mutants);
            }
        }

        return w.data;
    }
}

private:

// Mutation

/**
 * TODO: remove OpTypeInfo. It is just used to reduce the impact of the
 * refactoring.
 */
class MutantVisitor : analyze.DepthFirstVisitor {
    import dextool.plugin.mutate.backend.mutation_type.abs : absMutations;
    import dextool.plugin.mutate.backend.mutation_type.dcc : dccMutations;
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutations;
    import dextool.plugin.mutate.backend.mutation_type.sdl : stmtDelMutations;

    analyze.Ast* ast;
    MutantsResult result;

    private {
        uint depth;
        Stack!(analyze.Node) nstack;
    }

    this(analyze.Ast* ast, FilesysIO fio, ValidateLoc vloc) {
        this.ast = ast;
        result = new MutantsResult(ast.lang, fio, vloc);

        // by adding the locations here the rest of the visitor do not have to
        // be concerned about adding files.
        foreach (ref l; ast.locs.byValue) {
            result.put(l.file);
        }
    }

    void visitPush(analyze.Node n) {
        nstack.put(n, ++depth);
    }

    void visitPop() {
        nstack.pop;
        --depth;
    }

    /// Returns: true if the current node is inside a function that returns bool.
    bool isInsideBoolFunc() {
        if (auto rty = closestFuncType) {
            if (rty.kind == analyze.TypeKind.boolean) {
                return true;
            }
        }
        return false;
    }

    /// Returns: the depth (1+) if any of the parent nodes is `k`.
    uint isInside(analyze.Kind k) {
        foreach (a; nstack.range.filter!(a => a.data.kind == k)) {
            return a.depth;
        }
        return 0;
    }

    /// Returns: the type, if any, of the function that the current visited node is inside.
    auto closestFuncType() @trusted {
        foreach (n; nstack[].retro.filter!(a => a.data.kind == analyze.Kind.Function)) {
            auto fn = cast(analyze.Function) n.data;
            if (auto rty = ast.type(fn.return_)) {
                return rty;
            }
            break;
        }
        return null;
    }

    void put(analyze.Location loc, Mutation.Kind[] kinds) {
        foreach (kind; kinds) {
            result.put(loc.file, MutantsResult.MutationPoint(loc.interval, loc.sloc), kind);
        }
    }

    alias visit = analyze.DepthFirstVisitor.visit;

    override void visit(analyze.Expr n) {
        auto loc = ast.location(n);
        put(loc, absMutations(n.kind));

        if (isInsideBoolFunc && isInside(analyze.Kind.Return) && !isInside(analyze.Kind.Call)) {
            put(loc, dccMutations(n.kind));
            put(loc, dcrMutations(n.kind));
        }

        analyze.accept(n, this);
    }

    override void visit(analyze.Function n) {
        analyze.accept(n, this);
    }

    override void visit(analyze.Block n) @trusted {
        auto sdlAnalyze = scoped!SdlBlockVisitor(ast);
        sdlAnalyze.startVisit(n);
        if (sdlAnalyze.canRemove) {
            put(sdlAnalyze.loc, stmtDelMutations(n.kind));
        }

        analyze.accept(n, this);
    }

    override void visit(analyze.Call n) {
        auto loc = ast.location(n);

        if (ast.type(n) is null && !isInside(analyze.Kind.Return)) {
            // the check for Return blocks all SDL when an exception is thrown.
            //
            // a bit restricive to be begin with to only delete void returning
            // functions. Extend it in the future when it can "see" that the
            // return value is discarded.
            put(loc, stmtDelMutations(n.kind));
        }

        if (isInsideBoolFunc && isInside(analyze.Kind.Return)) {
            put(loc, dccMutations(n.kind));
            put(loc, dcrMutations(n.kind));
        }

        // should call visitOp

        analyze.accept(n, this);
    }

    override void visit(analyze.Return n) {
        if (closestFuncType is null) {
            // if the function return void then it is safe to delete the return.
            //
            // c++ throw expressions is modelled as returns with a child node
            // Call. Overall in any language it should be OK to remove a return
            // of something that returns void, the bottom type.
            put(ast.location(n), stmtDelMutations(n.kind));
        }

        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssign n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssignAdd n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssignAndBitwise n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssignDiv n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssignMod n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssignMul n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssignOrBitwise n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAssignSub n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        analyze.accept(n, this);
    }

    override void visit(analyze.OpNegate n) {
        visitUnaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAndBitwise n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAnd n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpOrBitwise n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpOr n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpLess n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpLessEq n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpGreater n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpGreaterEq n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpEqual n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpNotEqual n) {
        visitComparisonBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpAdd n) {
        visitArithmeticBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpSub n) {
        visitArithmeticBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpMul n) {
        visitArithmeticBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpMod n) {
        visitArithmeticBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.OpDiv n) {
        visitArithmeticBinaryOp(n);
        analyze.accept(n, this);
    }

    override void visit(analyze.Condition n) {
        auto kinds = dccMutations(n.kind);
        kinds ~= dcrMutations(n.kind);
        put(ast.location(n), kinds);
        analyze.accept(n, this);
    }

    override void visit(analyze.Branch n) {
        // only case statements have an inside. pretty bad "detection" but
        // works for now.
        if (n.inside !is null) {
            // removing the whole branch because then e.g. a switch-block would
            // jump to the default branch. It becomes "more" predictable what
            // happens compared to "falling through to the next case".
            put(ast.location(n), dcrMutations(n.kind));

            put(ast.location(n.inside), dccMutations(n.kind));
        }
        analyze.accept(n, this);
    }

    private void visitUnaryOp(T)(T n) {
        auto loc = ast.location(n);
        auto locExpr = ast.location(n.expr);
        auto locOp = ast.location(n.operator);

        Mutation.Kind[] expr, op;

        {
            import dextool.plugin.mutate.backend.mutation_type.uoi;

            op ~= uoiMutations(n.kind);
        }
        {
            expr ~= absMutations(n.kind);
        }

        put(loc, expr);
        put(locOp, op);
    }

    private void visitComparisonBinaryOp(T)(T n) {
        auto loc = ast.location(n);
        auto locLhs = ast.location(n.lhs);
        auto locRhs = ast.location(n.rhs);
        auto locOp = ast.location(n.operator);

        Mutation.Kind[] expr, op, lhs, rhs;

        {
            import dextool.plugin.mutate.backend.mutation_type.ror;

            auto m = rorMutations(RorInfo(n.kind, ast.type(n.lhs),
                    ast.symbol(n.lhs), ast.type(n.rhs), ast.symbol(n.rhs)));
            expr ~= m.expr;
            op ~= m.op;
        }
        {
            import dextool.plugin.mutate.backend.mutation_type.lcr;

            auto m = lcrMutations(n.kind);
            expr ~= m.expr;
            op ~= m.op;
            lhs ~= m.lhs;
            rhs ~= m.rhs;
        }
        {
            import dextool.plugin.mutate.backend.mutation_type.lcrb;

            auto m = lcrbMutations(n.kind);
            op ~= m.op;
            lhs ~= m.lhs;
            rhs ~= m.rhs;
        }
        {
            expr ~= absMutations(n.kind);
        }
        {
            expr ~= dcrMutations(n.kind);
            expr ~= dccMutations(n.kind);
        }

        put(loc, expr);
        put(locOp, op);
        if (n.lhs !is null) {
            auto offset = analyze.Interval(locLhs.interval.begin, locOp.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locLhs.sloc.begin, locOp.sloc.end)), lhs);
        }
        if (n.rhs !is null) {
            auto offset = analyze.Interval(locOp.interval.begin, locRhs.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locLhs.sloc.begin, locOp.sloc.end)), rhs);
        }
    }

    private void visitArithmeticBinaryOp(T)(T n) {
        auto loc = ast.location(n);
        auto locLhs = ast.location(n.lhs);
        auto locRhs = ast.location(n.rhs);
        auto locOp = ast.location(n.operator);

        Mutation.Kind[] op, lhs, rhs, expr;

        {
            expr ~= absMutations(n.kind);
        }
        {
            import dextool.plugin.mutate.backend.mutation_type.aor;

            auto m = aorMutations(n.kind);
            op ~= m.op;
            lhs ~= m.lhs;
            rhs ~= m.rhs;
        }

        put(loc, expr);
        put(locOp, op);
        if (n.lhs !is null) {
            auto offset = analyze.Interval(locLhs.interval.begin, locOp.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locLhs.sloc.begin, locOp.sloc.end)), lhs);
        }
        if (n.rhs !is null) {
            auto offset = analyze.Interval(locOp.interval.begin, locRhs.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locLhs.sloc.begin, locOp.sloc.end)), rhs);
        }
    }
}

/** Analyze a block to see if its content can be removed by the SDL mutation
 * operator.
 *
 * The block must:
 *  * contain something.
 *  * not contain a `Return` that returns a type other than void.
 */
class SdlBlockVisitor : analyze.DepthFirstVisitor {
    analyze.Ast* ast;

    // if the analyzer has determined that this node in the tree can be removed
    // with SDL. Note though that it doesn't know anything about the parent
    // node.
    bool canRemove;
    // if the block contains returns;
    bool hasReturn;
    /// The location that represent the block to remove.
    analyze.Location loc;

    this(analyze.Ast* ast) {
        this.ast = ast;
    }

    /// The node to start analysis from.
    void startVisit(analyze.Block n) {
        auto l = ast.location(n);

        if (l.interval.begin.among(l.interval.end, l.interval.end + 1, l.interval.end + 2)) {
            // it is an empty block so it can't be removed.
            return;
        }

        // the source range should also be modified but it isn't crucial for
        // mutation testing. Only the visualisation of the result.
        loc = new Location(l.file, analyze.Interval(l.interval.begin + 1,
                l.interval.end - 1), SourceLocRange(l.sloc.begin, l.sloc.end));
        canRemove = true;
        analyze.accept(n, this);
    }

    alias visit = analyze.DepthFirstVisitor.visit;

    override void visit(analyze.Block n) {
        analyze.accept(n, this);
    }

    override void visit(analyze.Return n) {
        hasReturn = true;

        // a return expression that is NOT void always have a child which is
        // the value returned.
        if (!n.children.empty) {
            canRemove = false;
        } else {
            analyze.accept(n, this);
        }
    }
}

// Schemata

class SchemataVisitor : analyze.DepthFirstVisitor {
    analyze.Ast* ast;

    this(analyze.Ast* ast) {
        this.ast = ast;
    }
}

// Clang AST

struct OperatorCursor {
    analyze.Expr astOp;

    // the whole expression
    analyze.Location exprLoc;
    DeriveCursorTypeResult exprTy;

    // the operator itself
    analyze.Operator operator;
    analyze.Location opLoc;

    Cursor lhs;
    Cursor rhs;

    /// Add the result to the AST and astOp to the parent.
    /// astOp is set to have two children, lhs and rhs.
    void put(analyze.Node parent, ref analyze.Ast ast) @safe {
        ast.put(astOp, exprLoc);
        ast.put(operator, opLoc);

        exprTy.put(ast);

        if (exprTy.type !is null)
            ast.put(astOp, exprTy.id);

        if (exprTy.symbol !is null)
            ast.put(astOp, exprTy.symId);

        parent.children ~= astOp;
    }
}

Nullable!OperatorCursor operatorCursor(T)(T node) {
    import dextool.clang_extensions : getExprOperator, OpKind, ValueKind, getUnderlyingExprNode;

    auto op = getExprOperator(node.cursor);
    if (!op.isValid)
        return typeof(return)();

    auto path = op.cursor.location.path.Path;
    if (path.empty)
        return typeof(return)();

    OperatorCursor res;

    void sidesPoint() {
        auto sides = op.sides;
        if (sides.lhs.isValid) {
            res.lhs = getUnderlyingExprNode(sides.lhs);
        }
        if (sides.rhs.isValid) {
            res.rhs = getUnderlyingExprNode(sides.rhs);
        }
    }

    // the operator itself
    void opPoint() {
        auto loc = op.location;
        auto sr = loc.spelling;
        res.operator = new analyze.Operator;
        res.opLoc = new analyze.Location(path, Interval(sr.offset,
                cast(uint)(sr.offset + op.length)), SourceLocRange(SourceLoc(loc.line,
                loc.column), SourceLoc(loc.line, cast(uint)(loc.column + op.length))));
    }

    // the arguments and the operator
    void exprPoint() {
        auto sr = op.cursor.extent;
        res.exprLoc = new analyze.Location(path, Interval(sr.start.offset,
                sr.end.offset), SourceLocRange(SourceLoc(sr.start.line,
                sr.start.column), SourceLoc(sr.end.line, sr.end.column)));
        res.exprTy = deriveCursorType(op.cursor);
        switch (op.kind) with (OpKind) {
        case OO_Star: // "*"
            goto case;
        case Mul: // "*"
            res.astOp = new analyze.OpMul;
            break;
        case OO_Slash: // "/"
            goto case;
        case Div: // "/"
            res.astOp = new analyze.OpDiv;
            break;
        case OO_Percent: // "%"
            goto case;
        case Rem: // "%"
            res.astOp = new analyze.OpMod;
            break;
        case OO_Plus: // "+"
            goto case;
        case Add: // "+"
            res.astOp = new analyze.OpAdd;
            break;
        case OO_Minus: // "-"
            goto case;
        case Sub: // "-"
            res.astOp = new analyze.OpSub;
            break;
        case OO_Less: // "<"
            goto case;
        case LT: // "<"
            res.astOp = new analyze.OpLess;
            break;
        case OO_Greater: // ">"
            goto case;
        case GT: // ">"
            res.astOp = new analyze.OpGreater;
            break;
        case OO_LessEqual: // "<="
            goto case;
        case LE: // "<="
            res.astOp = new analyze.OpLessEq;
            break;
        case OO_GreaterEqual: // ">="
            goto case;
        case GE: // ">="
            res.astOp = new analyze.OpGreaterEq;
            break;
        case OO_EqualEqual: // "=="
            goto case;
        case EQ: // "=="
            res.astOp = new analyze.OpEqual;
            break;
        case OO_Exclaim: // "!"
            goto case;
        case LNot: // "!"
            res.astOp = new analyze.OpNegate;
            break;
        case OO_ExclaimEqual: // "!="
            goto case;
        case NE: // "!="
            res.astOp = new analyze.OpNotEqual;
            break;
        case OO_AmpAmp: // "&&"
            goto case;
        case LAnd: // "&&"
            res.astOp = new analyze.OpAnd;
            break;
        case OO_PipePipe: // "||"
            goto case;
        case LOr: // "||"
            res.astOp = new analyze.OpOr;
            break;
        case OO_Amp: // "&"
            goto case;
        case And: // "&"
            res.astOp = new analyze.OpAndBitwise;
            break;
        case OO_Pipe: // "|"
            goto case;
        case Or: // "|"
            res.astOp = new analyze.OpOrBitwise;
            break;
        case OO_StarEqual: // "*="
            goto case;
        case MulAssign: // "*="
            res.astOp = new analyze.OpAssignMul;
            break;
        case OO_SlashEqual: // "/="
            goto case;
        case DivAssign: // "/="
            res.astOp = new analyze.OpAssignDiv;
            break;
        case OO_PercentEqual: // "%="
            goto case;
        case RemAssign: // "%="
            res.astOp = new analyze.OpAssignMod;
            break;
        case OO_PlusEqual: // "+="
            goto case;
        case AddAssign: // "+="
            res.astOp = new analyze.OpAssignAdd;
            break;
        case OO_MinusEqual: // "-="
            goto case;
        case SubAssign: // "-="
            res.astOp = new analyze.OpAssignSub;
            break;
        case OO_AmpEqual: // "&="
            goto case;
        case AndAssign: // "&="
            res.astOp = new analyze.OpAssignAndBitwise;
            break;
        case OrAssign: // "|="
            goto case;
        case OO_PipeEqual: // "|="
            res.astOp = new analyze.OpAssignOrBitwise;
            break;
        case ShlAssign: // "<<="
            goto case;
        case ShrAssign: // ">>="
            goto case;
        case XorAssign: // "^="
            goto case;
        case OO_CaretEqual: // "^="
            goto case;
        case OO_Equal: // "="
            goto case;
        case Assign: // "="
            res.astOp = new analyze.OpAssign;
            break;
            //case Xor: // "^"
            //case OO_Caret: // "^"
            //case OO_Tilde: // "~"
        default:
            res.astOp = new analyze.BinaryOp;
        }
    }

    exprPoint;
    opPoint;
    sidesPoint;
    return typeof(return)(res);
}

struct CaseStmtCursor {
    analyze.Location branch;
    analyze.Location insideBranch;

    Cursor inner;
}

Nullable!CaseStmtCursor caseStmtCursor(T)(T node) {
    import dextool.clang_extensions : getCaseStmt;

    auto mp = getCaseStmt(node.cursor);
    if (!mp.isValid)
        return typeof(return)();

    auto path = node.cursor.location.path.Path;
    if (path.empty)
        return typeof(return)();

    auto extent = node.cursor.extent;

    CaseStmtCursor res;
    res.inner = mp.subStmt;

    auto sr = res.inner.extent;
    auto insideLoc = SourceLocRange(SourceLoc(sr.start.line, sr.start.column),
            SourceLoc(sr.end.line, sr.end.column));
    auto offs = Interval(sr.start.offset, sr.end.offset);
    if (res.inner.kind == CXCursorKind.caseStmt) {
        auto colon = mp.colonLocation;
        insideLoc.begin = SourceLoc(colon.line, colon.column + 1);
        insideLoc.end = insideLoc.begin;

        // a case statement with fallthrough. the only point to inject a bomb
        // is directly after the semicolon
        offs.begin = colon.offset + 1;
        offs.end = offs.begin;
    } else if (res.inner.kind != CXCursorKind.compoundStmt) {
        offs.end = findTokenOffset(node.cursor.translationUnit.cursor.tokens,
                offs, CXTokenKind.punctuation);
    }

    void subStmt() {
        res.insideBranch = new analyze.Location(path, offs, insideLoc);
    }

    void stmt() {
        auto loc = extent.start;
        auto loc_end = extent.end;
        // reuse the end from offs because it covers either only the
        // fallthrough OR also the end semicolon
        auto stmt_offs = Interval(extent.start.offset, offs.end);
        res.branch = new analyze.Location(path, stmt_offs,
                SourceLocRange(SourceLoc(loc.line, loc.column),
                    SourceLoc(loc_end.line, loc_end.column)));
    }

    stmt;
    subStmt;
    return typeof(return)(res);
}

@safe:

Location toLocation(ref const Cursor c) {
    auto e = c.extent;
    auto interval = Interval(e.start.offset, e.end.offset);
    auto begin = e.start;
    auto end = e.end;
    return new Location(e.path.Path, interval, SourceLocRange(SourceLoc(begin.line,
            begin.column), SourceLoc(end.line, end.column)));
}

/** Find all mutation points that affect a whole expression.
 *
 * TODO change the name of the class. It is more than just an expression
 * visitor.
 *
 * # Usage of kind_stack
 * All usage of the kind_stack shall be documented here.
 *  - track assignments to avoid generating unary insert operators for the LHS.
 */
final class BaseVisitor : ExtendedVisitor {
    import clang.c.Index : CXCursorKind, CXTypeKind;
    import cpptooling.analyzer.clang.ast;
    import dextool.clang_extensions : getExprOperator, OpKind;

    alias visit = ExtendedVisitor.visit;

    // the depth the visitor is at.
    uint indent;
    // A stack of visited cursors up to the current one.
    Stack!Cursor cstack;
    Stack!(analyze.Node) nstack;

    /// The elements that where removed from the last decrement.
    Vector!(analyze.Node) lastDecr;

    analyze.Ast ast;

    this() nothrow {
    }

    override void incr() @safe {
        ++indent;
        lastDecr.clear;
    }

    override void decr() @trusted {
        --indent;

        cstack.popUntil(indent);
        lastDecr = nstack.popUntil(indent);
    }

    private void pushStack(T)(const T n) @trusted {
        // uncomment when it start being useful
        //cstack.put(n.cursor, indent);
    }

    private void pushStack(analyze.Node n) @trusted {
        nstack.put(n, indent);
    }

    private void pushStack(AstT, ClangT)(AstT n, ClangT v) @trusted {
        ast.put(n, v.cursor.toLocation);
        nstack.back.children ~= n;
        pushStack(n);
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        pushStack(v);

        ast.root = new analyze.TranslationUnit;
        ast.put(ast.root, v.cursor.toLocation);
        pushStack(ast.root);

        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        v.accept(this);
    }

    override void visit(const(Directive) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        v.accept(this);
    }

    override void visit(const(Reference) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        import cpptooling.analyzer.clang.ast : dispatch;
        import dextool.clang_extensions : getUnderlyingExprNode;

        mixin(mixinNodeLog!());
        pushStack(v);

        auto ue = Cursor(getUnderlyingExprNode(v.cursor));
        if (ue.isValid && ue != v.cursor) {
            incr;
            scope (exit)
                decr;
            dispatch(ue, this);
        } else {
            pushStack(new analyze.Expr, v);
            v.accept(this);
        }
    }

    override void visit(const(Preprocessor) v) {
        mixin(mixinNodeLog!());

        const bool isCpp = v.spelling == "__cplusplus";

        if (isCpp)
            ast.lang = Language.cpp;
        else if (ast.lang != Language.cpp)
            ast.lang = Language.c;

        v.accept(this);
    }

    override void visit(const(EnumDecl) v) @trusted {
        mixin(mixinNodeLog!());
        pushStack(v);

        import std.typecons : scoped;

        // extract the boundaries of the enum to update the type db.
        auto vis = scoped!EnumVisitor(indent);
        vis.visit(v);
        ast.types.set(vis.id, vis.toType);
    }

    override void visit(const(FunctionDecl) v) @trusted {
        mixin(mixinNodeLog!());
        pushStack(v);
        visitFunc(v);
    }

    override void visit(const(CxxMethod) v) {
        mixin(mixinNodeLog!());
        pushStack(v);

        // model C++ methods as functions. It should be enough to know that it
        // is a function and the return type when generating mutants.
        visitFunc(v);
    }

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());
        pushStack(v);

        if (!visitOp(v)) {
            pushStack(new analyze.Call, v);
            v.accept(this);
        }
    }

    override void visit(const(BreakStmt) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        v.accept(this);
    }

    override void visit(const BinaryOperator v) @trusted {
        mixin(mixinNodeLog!());
        pushStack(v);
        visitOp(v);
    }

    override void visit(const UnaryOperator v) @trusted {
        mixin(mixinNodeLog!());
        pushStack(v);
        visitOp(v);
    }

    override void visit(const CompoundAssignOperator v) {
        mixin(mixinNodeLog!());
        pushStack(v);

        // TODO: implement all aor assignment such as +=
        pushStack(new analyze.OpAssign, v);

        v.accept(this);
    }

    override void visit(const CxxThrowExpr v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        // model a C++ exception as a return expression because that is
        // "basically" what happens.
        pushStack(new analyze.Return, v);
        v.accept(this);
    }

    override void visit(const(ReturnStmt) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        pushStack(new analyze.Return, v);
        v.accept(this);
    }

    override void visit(const(CompoundStmt) v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        pushStack(new analyze.Block, v);
        v.accept(this);
    }

    override void visit(const CaseStmt v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        visitCaseStmt(v);
    }

    override void visit(const DefaultStmt v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        visitCaseStmt(v);
    }

    override void visit(const IfStmt v) @trusted {
        mixin(mixinNodeLog!());
        pushStack(v);
        pushStack(new analyze.Block, v);
        dextool.plugin.mutate.backend.analyze.extensions.accept(v, this);
    }

    override void visit(const IfStmtCond v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        pushStack(new analyze.Condition, v);

        incr;
        scope (exit)
            decr;
        if (!visitOp(v)) {
            v.accept(this);
        }
    }

    override void visit(const IfStmtThen v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        pushStack(new analyze.Branch, v);
        v.accept(this);
    }

    override void visit(const IfStmtElse v) {
        mixin(mixinNodeLog!());
        pushStack(v);
        pushStack(new analyze.Branch, v);
        v.accept(this);
    }

    private bool visitOp(T)(ref const T v) @trusted {
        auto op = operatorCursor(v);
        if (op.isNull) {
            return false;
        }

        if (visitBinaryOp(op.get))
            return true;
        return visitUnaryOp(op.get);
    }

    /// Returns: true if it added a binary operator, false otherwise.
    private bool visitBinaryOp(ref OperatorCursor op) @trusted {
        import cpptooling.analyzer.clang.ast : dispatch;

        auto astOp = cast(analyze.BinaryOp) op.astOp;
        if (astOp is null)
            return false;

        astOp.operator = op.operator;

        op.put(nstack.back, ast);
        pushStack(astOp);
        incr;
        scope (exit)
            decr;

        if (op.lhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.lhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.lhs = b;
                auto ty = deriveCursorType(op.lhs);
                ty.put(ast);
                if (ty.type !is null) {
                    ast.put(b, ty.id);
                }
                if (ty.symbol !is null) {
                    ast.put(b, ty.symId);
                }
            }
        }
        if (op.rhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.rhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.rhs = b;
                auto ty = deriveCursorType(op.rhs);
                ty.put(ast);
                if (ty.type !is null) {
                    ast.put(b, ty.id);
                }
                if (ty.symbol !is null) {
                    ast.put(b, ty.symId);
                }
            }
        }

        return true;
    }

    /// Returns: true if it added a binary operator, false otherwise.
    private bool visitUnaryOp(ref OperatorCursor op) @trusted {
        import cpptooling.analyzer.clang.ast : dispatch;

        auto astOp = cast(analyze.UnaryOp) op.astOp;
        if (astOp is null)
            return false;

        astOp.operator = op.operator;

        op.put(nstack.back, ast);
        pushStack(astOp);
        incr;
        scope (exit)
            decr;

        if (op.lhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.lhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.expr = b;
                auto ty = deriveCursorType(op.lhs);
                ty.put(ast);
                if (ty.type !is null) {
                    ast.put(b, ty.id);
                }
                if (ty.symbol !is null) {
                    ast.put(b, ty.symId);
                }
            }
        } else if (op.rhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.rhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.expr = b;
                auto ty = deriveCursorType(op.rhs);
                ty.put(ast);
                if (ty.type !is null) {
                    ast.put(b, ty.id);
                }
                if (ty.symbol !is null) {
                    ast.put(b, ty.symId);
                }
            }
        }

        return true;
    }

    private void visitFunc(T)(ref const T v) @trusted {
        auto loc = v.cursor.toLocation;
        auto n = new analyze.Function;
        ast.put(n, loc);
        nstack.back.children ~= n;
        pushStack(n);

        auto fRetval = new analyze.Return;
        auto rty = deriveType(v.cursor.func.resultType);
        rty.put(ast);
        if (rty.type !is null) {
            ast.put(fRetval, loc);
            n.return_ = fRetval;
            ast.put(fRetval, rty.id);
        }
        if (rty.symbol !is null) {
            ast.put(fRetval, rty.symId);
        }

        v.accept(this);
    }

    private void visitCaseStmt(T)(ref const T v) @trusted {
        auto res = caseStmtCursor(v);
        if (res.isNull) {
            pushStack(new analyze.Block, v);
            v.accept(this);
            return;
        }

        auto branch = new analyze.Branch;
        ast.put(branch, res.get.branch);
        nstack.back.children ~= branch;
        pushStack(branch);

        // create an node depth that diverge from the clang AST wherein the
        // inside of a case stmt is modelled as a block.
        incr;
        scope (exit)
            decr;
        auto inner = new analyze.Block;
        ast.put(inner, res.get.insideBranch);
        branch.children ~= inner;
        branch.inside = inner;
        pushStack(inner);
        dispatch(res.get.inner, this);
    }
}

final class EnumVisitor : ExtendedVisitor {
    import std.typecons : Nullable;
    import cpptooling.analyzer.clang.ast;

    alias visit = ExtendedVisitor.visit;

    mixin generateIndentIncrDecr;

    analyze.TypeId id;
    Nullable!long minValue;
    Nullable!long maxValue;

    this(const uint indent) {
        this.indent = indent;
    }

    override void visit(const EnumDecl v) @trusted {
        mixin(mixinNodeLog!());
        id = make!(analyze.TypeId)(v.cursor);
        v.accept(this);
    }

    override void visit(const EnumConstantDecl v) @trusted {
        mixin(mixinNodeLog!());

        long value = v.cursor.enum_.signedValue;

        if (minValue.isNull) {
            minValue = value;
            maxValue = value;
        }

        if (value < minValue.get)
            minValue = value;
        if (value > maxValue.get)
            maxValue = value;

        v.accept(this);
    }

    analyze.Type toType() const {
        auto l = () {
            if (minValue.isNull)
                return analyze.Value(analyze.Value.NegInf.init);
            return analyze.Value(analyze.Value.Int(minValue.get));
        }();
        auto u = () {
            if (maxValue.isNull)
                return analyze.Value(analyze.Value.PosInf.init);
            return analyze.Value(analyze.Value.Int(maxValue.get));
        }();

        return new analyze.DiscreteType(analyze.Range(l, u));
    }
}

enum discreteCategory = AliasSeq!(CXTypeKind.charU, CXTypeKind.uChar, CXTypeKind.char16,
            CXTypeKind.char32, CXTypeKind.uShort, CXTypeKind.uInt, CXTypeKind.uLong, CXTypeKind.uLongLong,
            CXTypeKind.uInt128, CXTypeKind.charS, CXTypeKind.sChar, CXTypeKind.wChar, CXTypeKind.short_,
            CXTypeKind.int_, CXTypeKind.long_, CXTypeKind.longLong,
            CXTypeKind.int128, CXTypeKind.enum_,);
enum floatCategory = AliasSeq!(CXTypeKind.float_, CXTypeKind.double_,
            CXTypeKind.longDouble, CXTypeKind.float128, CXTypeKind.half, CXTypeKind.float16,);
enum pointerCategory = AliasSeq!(CXTypeKind.nullPtr, CXTypeKind.pointer,
            CXTypeKind.blockPointer, CXTypeKind.memberPointer);
enum boolCategory = AliasSeq!(CXTypeKind.bool_);

struct DeriveTypeResult {
    analyze.TypeId id;
    analyze.Type type;
    analyze.SymbolId symId;
    analyze.Symbol symbol;

    void put(ref analyze.Ast ast) @safe {
        if (type !is null) {
            ast.types.require(id, type);
        }
        if (symbol !is null) {
            ast.symbols.require(symId, symbol);
        }
    }
}

DeriveTypeResult deriveType(Type cty) {
    DeriveTypeResult rval;

    auto ctydecl = cty.declaration;
    if (ctydecl.isValid) {
        rval.id = make!(analyze.TypeId)(ctydecl);
    } else {
        rval.id = make!(analyze.TypeId)(cty.cursor);
    }

    if (cty.isEnum) {
        rval.type = new analyze.DiscreteType(analyze.Range.makeInf);
        if (!cty.isSigned) {
            rval.type.range.low = analyze.Value(analyze.Value.Int(0));
        }
    } else if (cty.kind.among(floatCategory)) {
        rval.type = new analyze.ContinuesType(analyze.Range.makeInf);
    } else if (cty.kind.among(pointerCategory)) {
        rval.type = new analyze.UnorderedType(analyze.Range.makeInf);
    } else if (cty.kind.among(boolCategory)) {
        rval.type = new analyze.BooleanType(analyze.Range.makeBoolean);
    } else if (cty.kind.among(discreteCategory)) {
        rval.type = new analyze.DiscreteType(analyze.Range.makeInf);
        if (!cty.isSigned) {
            rval.type.range.low = analyze.Value(analyze.Value.Int(0));
        }
    }

    return rval;
}

struct DeriveCursorTypeResult {
    Cursor expr;
    DeriveTypeResult typeResult;
    alias typeResult this;
}

/** Analyze a cursor to derive the type of it and if it has a concrete value
 * and what it is in that case.
 *
 * This is intended for expression nodes in the clang AST.
 */
DeriveCursorTypeResult deriveCursorType(const Cursor baseCursor) {
    auto c = Cursor(getUnderlyingExprNode(baseCursor));
    if (!c.isValid)
        return DeriveCursorTypeResult.init;

    auto rval = DeriveCursorTypeResult(c);
    auto cty = c.type.canonicalType;
    rval.typeResult = deriveType(cty);

    // evaluate the cursor to add a value for the symbol
    void eval(const ref Eval e) {
        if (!e.kind.among(CXEvalResultKind.int_))
            return;

        const long value = () {
            if (e.isUnsignedInt) {
                const v = e.asUnsigned;
                if (v < long.max)
                    return cast(long) v;
            }
            return e.asLong;
        }();

        rval.symId = make!(analyze.SymbolId)(c);
        rval.symbol = new analyze.DiscretSymbol(analyze.Value(analyze.Value.Int(value)));
    }

    if (cty.isEnum) {
        // TODO: check if c.eval give the same result. If so it may be easier
        // to remove this special case of an enum because it is covered by the
        // generic branch for discretes.

        auto ctydecl = cty.declaration;
        if (!ctydecl.isValid)
            return rval;

        const cref = c.referenced;
        if (!cref.isValid)
            return rval;

        if (cref.kind == CXCursorKind.enumConstantDecl) {
            const long value = cref.enum_.signedValue;
            rval.symId = make!(analyze.SymbolId)(c);
            rval.symbol = new analyze.DiscretSymbol(analyze.Value(analyze.Value.Int(value)));
        }
    } else if (cty.kind.among(discreteCategory)) {
        const e = c.eval;
        if (e.isValid)
            eval(e);
    }

    return rval;
}

/** Inject code to validate and check the location of a cursor.
 *
 * Params:
 *   cursor = code snippet to get the cursor from a variable accessable in the method.
 */
string makeAndCheckLocation(string cursor) {
    import std.format : format;

    return format(q{
        auto extent = %s.extent;
        auto loc = extent.start;
        auto loc_end = extent.end;
    if (!val_loc.shouldAnalyze(loc.path)) {
        return;
    }}, cursor);
}

struct Stack(T) {
    import std.typecons : Tuple;

    alias Element = Tuple!(T, "data", uint, "depth");
    Vector!(Element) stack;

    alias stack this;

    // trusted: as long as arr do not escape the instance
    void put(T a, uint depth) @trusted {
        stack.put(Element(a, depth));
    }

    // trusted: as long as arr do not escape the instance
    void pop() @trusted {
        stack.popBack;
    }

    /**
     * It is important that it removes up to and including the specified depth
     * because the stack is used when doing depth first search. Each call to
     * popUntil is expected to remove a layer. New nodes are then added to the
     * parent which is the first one from the previous layer.
     *
     * Returns: the removed elements.
     */
    auto popUntil(uint depth) @trusted {
        Vector!T rval;
        while (!stack.empty && stack[$ - 1].depth >= depth) {
            rval.put(stack[$ - 1].data);
            stack.popBack;
        }
        return rval;
    }

    T back() {
        return stack[$ - 1].data;
    }

    bool empty() @safe pure nothrow const @nogc {
        return stack.empty;
    }
}

auto make(T)(const Cursor c) if (is(T == analyze.TypeId) || is(T == analyze.SymbolId)) {
    const usr = c.usr;
    if (usr.empty) {
        return T(c.toHash);
    }
    return analyze.makeId!T(usr);
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
