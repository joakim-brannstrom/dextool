/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.pass_mutant;

import logger = std.experimental.logger;
import std.algorithm : among, map, sort, filter;
import std.array : appender, empty, array, Appender;
import std.exception : collectException;
import std.format : formattedWrite;
import std.range : retro, ElementType;
import std.typecons : tuple, Tuple, scoped;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast;
import dextool.plugin.mutate.backend.analyze.internal : TokenStream;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.type : Language, Offset, Mutation, SourceLocRange, Token;

@safe:

/// Find mutants.
MutantsResult toMutants(ref Ast ast, FilesysIO fio, ValidateLoc vloc) {
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
class MutantVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.mutation_type.abs : absMutations;
    import dextool.plugin.mutate.backend.mutation_type.dcc : dccMutations;
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutations;
    import dextool.plugin.mutate.backend.mutation_type.sdl : stmtDelMutations;

    Ast* ast;
    MutantsResult result;

    private {
        uint depth;
        Stack!(Node) nstack;
    }

    this(Ast* ast, FilesysIO fio, ValidateLoc vloc) {
        this.ast = ast;
        result = new MutantsResult(ast.lang, fio, vloc);

        // by adding the locations here the rest of the visitor do not have to
        // be concerned about adding files.
        foreach (ref l; ast.locs.byValue) {
            result.put(l.file);
        }
    }

    void visitPush(Node n) {
        nstack.put(n, ++depth);
    }

    void visitPop() {
        nstack.pop;
        --depth;
    }

    /// Returns: true if the current node is inside a function that returns bool.
    bool isInsideBoolFunc() {
        if (auto rty = closestFuncType) {
            if (rty.kind == TypeKind.boolean) {
                return true;
            }
        }
        return false;
    }

    /// Returns: the depth (1+) if any of the parent nodes is `k`.
    uint isInside(Kind k) {
        foreach (a; nstack.range.filter!(a => a.data.kind == k)) {
            return a.depth;
        }
        return 0;
    }

    /// Returns: the type, if any, of the function that the current visited node is inside.
    auto closestFuncType() @trusted {
        foreach (n; nstack[].retro.filter!(a => a.data.kind == Kind.Function)) {
            auto fn = cast(Function) n.data;
            if (auto rty = ast.type(fn.return_)) {
                return rty;
            }
            break;
        }
        return null;
    }

    void put(Location loc, Mutation.Kind[] kinds) {
        foreach (kind; kinds) {
            result.put(loc.file, MutantsResult.MutationPoint(loc.interval, loc.sloc), kind);
        }
    }

    alias visit = DepthFirstVisitor.visit;

    override void visit(Expr n) {
        auto loc = ast.location(n);
        put(loc, absMutations(n.kind));

        if (isInsideBoolFunc && isInside(Kind.Return) && !isInside(Kind.Call)) {
            put(loc, dccMutations(n.kind));
            put(loc, dcrMutations(n.kind));
        }

        accept(n, this);
    }

    override void visit(Function n) {
        accept(n, this);
    }

    override void visit(Block n) @trusted {
        auto sdlAnalyze = scoped!SdlBlockVisitor(ast);
        sdlAnalyze.startVisit(n);
        if (sdlAnalyze.canRemove) {
            put(sdlAnalyze.loc, stmtDelMutations(n.kind));
        }

        accept(n, this);
    }

    override void visit(Call n) {
        auto loc = ast.location(n);

        if (ast.type(n) is null && !isInside(Kind.Return)) {
            // the check for Return blocks all SDL when an exception is thrown.
            //
            // a bit restricive to be begin with to only delete void returning
            // functions. Extend it in the future when it can "see" that the
            // return value is discarded.
            put(loc, stmtDelMutations(n.kind));
        }

        if (isInsideBoolFunc && isInside(Kind.Return)) {
            put(loc, dccMutations(n.kind));
            put(loc, dcrMutations(n.kind));
        }

        // should call visitOp

        accept(n, this);
    }

    override void visit(Return n) {
        if (closestFuncType is null) {
            // if the function return void then it is safe to delete the return.
            //
            // c++ throw expressions is modelled as returns with a child node
            // Call. Overall in any language it should be OK to remove a return
            // of something that returns void, the bottom type.
            put(ast.location(n), stmtDelMutations(n.kind));
        }

        accept(n, this);
    }

    override void visit(OpAssign n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpAssignAdd n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpAssignAndBitwise n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpAssignDiv n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpAssignMod n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpAssignMul n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpAssignOrBitwise n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpAssignSub n) {
        put(ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(OpNegate n) {
        visitUnaryOp(n);
        accept(n, this);
    }

    override void visit(OpAndBitwise n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpAnd n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpOrBitwise n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpOr n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpLess n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpLessEq n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpGreater n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpGreaterEq n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpEqual n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpNotEqual n) {
        visitComparisonBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpAdd n) {
        visitArithmeticBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpSub n) {
        visitArithmeticBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpMul n) {
        visitArithmeticBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpMod n) {
        visitArithmeticBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpDiv n) {
        visitArithmeticBinaryOp(n);
        accept(n, this);
    }

    override void visit(Condition n) {
        auto kinds = dccMutations(n.kind);
        kinds ~= dcrMutations(n.kind);
        put(ast.location(n), kinds);
        accept(n, this);
    }

    override void visit(Branch n) {
        // only case statements have an inside. pretty bad "detection" but
        // works for now.
        if (n.inside !is null) {
            // removing the whole branch because then e.g. a switch-block would
            // jump to the default branch. It becomes "more" predictable what
            // happens compared to "falling through to the next case".
            put(ast.location(n), dcrMutations(n.kind));

            put(ast.location(n.inside), dccMutations(n.kind));
        }
        accept(n, this);
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
            auto offset = Interval(locLhs.interval.begin, locOp.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locLhs.sloc.begin, locOp.sloc.end)), lhs);
        }
        if (n.rhs !is null) {
            auto offset = Interval(locOp.interval.begin, locRhs.interval.end);
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
            auto offset = Interval(locLhs.interval.begin, locOp.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locLhs.sloc.begin, locOp.sloc.end)), lhs);
        }
        if (n.rhs !is null) {
            auto offset = Interval(locOp.interval.begin, locRhs.interval.end);
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
class SdlBlockVisitor : DepthFirstVisitor {
    Ast* ast;

    // if the analyzer has determined that this node in the tree can be removed
    // with SDL. Note though that it doesn't know anything about the parent
    // node.
    bool canRemove;
    // if the block contains returns;
    bool hasReturn;
    /// The location that represent the block to remove.
    Location loc;

    this(Ast* ast) {
        this.ast = ast;
    }

    /// The node to start analysis from.
    void startVisit(Block n) {
        auto l = ast.location(n);

        if (l.interval.begin.among(l.interval.end, l.interval.end + 1, l.interval.end + 2)) {
            // it is an empty block so it can't be removed.
            return;
        }

        // the source range should also be modified but it isn't crucial for
        // mutation testing. Only the visualisation of the result.
        loc = new Location(l.file, Interval(l.interval.begin + 1,
                l.interval.end - 1), SourceLocRange(l.sloc.begin, l.sloc.end));
        canRemove = true;
        accept(n, this);
    }

    alias visit = DepthFirstVisitor.visit;

    override void visit(Block n) {
        accept(n, this);
    }

    override void visit(Return n) {
        hasReturn = true;

        // a return expression that is NOT void always have a child which is
        // the value returned.
        if (!n.children.empty) {
            canRemove = false;
        } else {
            accept(n, this);
        }
    }
}
