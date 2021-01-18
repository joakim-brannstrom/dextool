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

import my.gc.refc : RefCounted;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast;
import dextool.plugin.mutate.backend.analyze.internal : TokenStream;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.type : Language, Offset, Mutation, SourceLocRange, Token;

@safe:

/// Find mutants.
MutantsResult toMutants(RefCounted!Ast ast, FilesysIO fio, ValidateLoc vloc, Mutation.Kind[] kinds) @safe {
    auto visitor = new MutantVisitor(ast, fio, vloc, kinds);
    scope (exit)
        visitor.dispose;
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
            // use this to easily find zero length mutants.
            // note though that it can't always be active because it has
            // some false positives such as dccBomb
            //if (mp.point.offset.begin == mp.point.offset.end) {
            //    logger.warningf("Malformed mutant (begin == end), dropping. %s %s %s %s",
            //            mp.kind, mp.point.offset, mp.point.sloc, f);
            //}

            if (mp.point.offset.begin > mp.point.offset.end) {
                logger.warningf("Malformed mutant (begin > end), dropping. %s %s %s %s",
                        mp.kind, mp.point.offset, mp.point.sloc, f);
            } else {
                result.put(f, mp.point.offset, mp.point.sloc, mp.kind);
            }
        }
    }

    return result;
}

class MutantsResult {
    import dextool.plugin.mutate.backend.type : Checksum;
    import my.set;

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
        Set!(Mutation.Kind) kinds;
    }

    this(const Language lang, FilesysIO fio, ValidateLoc vloc, Mutation.Kind[] kinds) {
        this.lang = lang;
        this.fio = fio;
        this.vloc = vloc;
        this.kinds = toSet(kinds);
    }

    Tuple!(Mutation.Kind[], "kind", MutationPoint, "point")[] getMutationPoints(AbsolutePath file) @safe pure nothrow const {
        alias RType = ElementType!(typeof(return));
        return points[file].byKeyValue.map!(a => RType(a.value.toArray, a.key)).array;
    }

    /// Drop a mutant.
    void drop(AbsolutePath p, MutationPoint mp, Mutation.Kind kind) @safe {
        if (auto a = p in points) {
            if (auto b = mp in *a) {
                (*b).remove(kind);
                if (b.empty)
                    (*a).remove(mp);
            }
        }
    }

    private void put(AbsolutePath absp) @trusted {
        import dextool.plugin.mutate.backend.utility : checksum;

        if (!vloc.shouldMutate(absp) || absp in existingFiles)
            return;

        try {
            auto fin = fio.makeInput(absp);
            auto cs = checksum(fin.content);

            existingFiles.add(absp);
            files ~= ElementType!(typeof(files))(absp, cs);
            points[absp] = (Set!(Mutation.Kind)[MutationPoint]).init;
        } catch (Exception e) {
            logger.warningf("%s: %s", absp, e.msg);
        }
    }

    private void put(AbsolutePath p, MutationPoint mp, Mutation.Kind kind) @safe {
        if (kind !in kinds) {
            return;
        }

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

        put(w, "MutantsResult\n");
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
    import my.hash : Checksum128, BuildChecksum128, toBytes, toChecksum128;
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

        /// Current filename that the id factory is initialized with.
        AbsolutePath idFileName;
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

        if (p != idFileName) {
            idFileName = p;
            tokens = tstream.getFilteredTokens(p);
            idFactory = MutationIdFactory(fio.toRelativeRoot(p), tokens);
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

class MutantVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutations, DcrInfo;
    import dextool.plugin.mutate.backend.mutation_type.sdl : stmtDelMutations;

    RefCounted!Ast ast;
    MutantsResult result;

    private {
        uint depth;
        Stack!(Node) nstack;
    }

    alias visit = DepthFirstVisitor.visit;

    this(RefCounted!Ast ast, FilesysIO fio, ValidateLoc vloc, Mutation.Kind[] kinds) {
        this.ast = ast;
        result = new MutantsResult(ast.lang, fio, vloc, kinds);

        // by adding the locations here the rest of the visitor do not have to
        // be concerned about adding files.
        foreach (ref l; ast.locs.byValue) {
            result.put(l.file);
        }
    }

    void dispose() {
        ast.release;
    }

    override void visitPush(Node n) {
        nstack.put(n, ++depth);
    }

    override void visitPop(Node n) {
        nstack.pop;
        --depth;
    }

    /// Returns: the closest function from the current node.
    Function getClosestFunc() {
        return cast(Function) match!((a) {
            if (a[0].data.kind == Kind.Function)
                return a[0].data;
            return null;
        })(nstack, Direction.bottomToTop);
    }

    /// Returns: true if the current node is inside a function that returns bool.
    bool isParentBoolFunc() {
        if (auto rty = closestFuncType) {
            if (rty.kind == TypeKind.boolean) {
                return true;
            }
        }
        return false;
    }

    /// Returns: the depth (1+) if any of the parent nodes is `k`.
    uint isParent(Kind k) {
        return nstack.isParent(k);
    }

    /// Returns: if the previous nodes is of kind `k`.
    bool isDirectParent(Kind k) {
        if (nstack.empty)
            return false;
        return nstack.back.kind == k;
    }

    /// Returns: the type, if any, of the function that the current visited node is inside.
    Type closestFuncType() @trusted {
        auto f = getClosestFunc;
        if (f is null)
            return null;
        return ast.type(f.return_);
    }

    /// Returns: a range of all types of the children of `n`.
    auto allTypes(Node n) {
        return n.children
            .map!(a => ast.type(a))
            .filter!(a => a !is null);
    }

    /// Returns: a range of all kinds of the children of `n`.
    void put(Location loc, Mutation.Kind[] kinds, const bool blacklist) {
        if (blacklist)
            return;

        foreach (kind; kinds) {
            result.put(loc.file, MutantsResult.MutationPoint(loc.interval, loc.sloc), kind);
        }
    }

    override void visit(Expr n) {
        auto loc = ast.location(n);

        if (isParentBoolFunc && isParent(Kind.Return) && !isParent(Kind.Call)) {
            put(loc, dcrMutations(DcrInfo(n.kind, ast.type(n))), n.blacklist);
        }

        accept(n, this);
    }

    override void visit(Block n) {
        sdlBlock(n, stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(Loop n) {
        sdlBlock(n, stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(BranchBundle n) {
        sdlBlock(n, stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(Call n) {
        // the check isParent..:
        // e.g. a C++ class constructor calls a members constructor in its
        // initialization list.
        // TODO: is this needed? I do not think so considering the rest of the
        // code.

        if (isParent(Kind.Function) && ast.type(n) is null
                && !isParent(Kind.Return) && isDirectParent(Kind.Block)) {
            // the check for Return blocks all SDL when an exception is thrown.
            //
            // the check isDirectParent(Kind.Block) is to only delete function
            // or method calls that are at the root of a chain of calls in the
            // AST.
            //
            // a bit restricive to be begin with to only delete void returning
            // functions. Extend it in the future when it can "see" that the
            // return value is discarded.
            auto loc = ast.location(n);
            put(loc, stmtDelMutations(n.kind), n.blacklist);
        }

        // should call visitOp
        accept(n, this);
    }

    override void visit(Return n) {
        auto ty = closestFuncType;
        auto loc = ast.location(n);

        if (ty !is null && ty.kind == TypeKind.top) {
            // only function with return type void (top, no type) can be
            // deleted without introducing undefined behavior.
            put(loc, stmtDelMutations(n.kind), n.blacklist);
        }

        put(loc, dcrMutations(DcrInfo(n.kind, ty)), n.blacklist);

        accept(n, this);
    }

    override void visit(BinaryOp n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssign n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssignAdd n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssignAndBitwise n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssignDiv n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssignMod n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssignMul n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssignOrBitwise n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(OpAssignSub n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
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
        put(ast.location(n), dcrMutations(DcrInfo(n.kind, ast.type(n))), n.blacklist);
        accept(n, this);
    }

    override void visit(Branch n) {
        // only case statements have an inside. pretty bad "detection" but
        // works for now.
        if (n.inside !is null) {
            // removing the whole branch because then e.g. a switch-block would
            // jump to the default branch. It becomes "more" predictable what
            // happens compared to "falling through to the next case".
            put(ast.location(n.inside), dcrMutations(DcrInfo(n.kind, ast.type(n))), n.blacklist);

            sdlBlock(n.inside, stmtDelMutations(n.kind));
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

            expr ~= uoiMutations(n.kind);
        }
        if (isDirectParent(Kind.Block)) {
            expr ~= stmtDelMutations(n.kind);
        }

        put(loc, expr, n.blacklist);
        put(locOp, op, n.operator.blacklist);
    }

    private void visitComparisonBinaryOp(T)(T n) {
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
            auto nty = ast.type(n);
            expr ~= dcrMutations(DcrInfo(n.kind, ast.type(n)));
        }
        if (isDirectParent(Kind.Block)) {
            expr ~= stmtDelMutations(n.kind);
        }

        visitBinaryOp(n, op, lhs, rhs, expr);
    }

    private void visitArithmeticBinaryOp(T)(T n) {
        Mutation.Kind[] op, lhs, rhs, expr;

        {
            import dextool.plugin.mutate.backend.mutation_type.aor;

            auto m = aorMutations(AorInfo(n.kind, ast.type(n.lhs), ast.type(n.rhs)));
            op ~= m.op;
            lhs ~= m.lhs;
            rhs ~= m.rhs;
        }
        {
            import dextool.plugin.mutate.backend.mutation_type.aors;

            op ~= aorsMutations(n.kind);
        }
        if (isDirectParent(Kind.Block)) {
            expr ~= stmtDelMutations(n.kind);
        }

        visitBinaryOp(n, op, lhs, rhs, expr);
    }

    private void visitBinaryOp(T)(T n, Mutation.Kind[] op, Mutation.Kind[] lhs,
            Mutation.Kind[] rhs, Mutation.Kind[] expr) {
        auto locExpr = ast.location(n);
        auto locOp = ast.location(n.operator);

        put(locExpr, expr, n.blacklist);
        put(locOp, op, n.operator.blacklist);
        // the interval check:
        // != is sufficiently for unary operators such as ++.
        // but there are also malformed that can be created thus '<' is needed.
        // Change this to != and run on the game tutorial to see them being
        // produced. Seems to be something with templates and function calls.
        if (n.lhs !is null && locExpr.interval.begin < locOp.interval.end) {
            auto offset = Interval(locExpr.interval.begin, locOp.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locExpr.sloc.begin, locOp.sloc.end)), lhs, n.lhs.blacklist);
        }
        if (n.rhs !is null && locOp.interval.begin < locExpr.interval.end) {
            auto offset = Interval(locOp.interval.begin, locExpr.interval.end);
            put(new Location(locOp.file, offset,
                    SourceLocRange(locOp.sloc.begin, locExpr.sloc.end)), rhs, n.rhs.blacklist);
        }
    }

    private void sdlBlock(T)(T n, Mutation.Kind[] op) @trusted {
        auto sdlAnalyze = scoped!DeleteBlockVisitor(ast);
        sdlAnalyze.startVisit(n);

        if (sdlAnalyze.canRemove) {
            put(sdlAnalyze.loc, op, n.blacklist);
        }
    }
}

/** Analyze a block to see if its content can be removed without introducing
 * any undefined behavior.
 *
 * The block must:
 *  * contain something.
 *  * not contain a `Return` that returns a type other than void.
 */
class DeleteBlockVisitor : DepthFirstVisitor {
    RefCounted!Ast ast;

    // if the analyzer has determined that this node in the tree can be removed
    // with SDL. Note though that it doesn't know anything about the parent
    // node.
    bool canRemove = true;
    /// The location that represent the block to remove.
    Location loc;

    alias visit = DepthFirstVisitor.visit;

    this(RefCounted!Ast ast) {
        this.ast = ast;
    }

    /// The node to start analysis from.
    void startVisit(Node n) {
        auto l = ast.location(n);

        if (l.interval.end.among(l.interval.begin, l.interval.begin + 1)) {
            // it is an empty block so it can't be removed.
            canRemove = false;
        } else if (l.interval.begin < l.interval.end) {
            loc = l;
            visit(n);
        } else {
            // something is wrong with the location.... this should never
            // happen.
            canRemove = false;
        }
    }

    override void visit(Return n) {
        if (n.children.empty) {
            accept(n, this);
        } else {
            canRemove = false;
        }
    }
}
