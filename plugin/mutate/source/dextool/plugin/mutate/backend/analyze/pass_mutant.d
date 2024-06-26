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
import std.typecons : tuple, Tuple;

static import colorlog;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast;
import dextool.plugin.mutate.backend.analyze.internal : TokenStream;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.type : Language, Offset, Mutation, SourceLocRange, Token;
import dextool.plugin.mutate.type : MutantIdGeneratorConfig;

alias log = colorlog.log!"analyze.pass_mutant";

shared static this() {
    colorlog.make!(colorlog.SimpleLogger)(logger.LogLevel.info, "analyze.pass_mutant");
}

@safe:

/// Find mutants.
MutantsResult toMutants(Ast* ast, FilesysIO fio, ValidateLoc vloc, Mutation.Kind[] kinds) {
    scope visitor = new FindRootVisitor(ast, fio, vloc, kinds);
    () @trusted { ast.accept(visitor); }();
    return visitor.result;
}

/// Filter the mutants and add checksums.
CodeMutantsResult toCodeMutants(MutantsResult mutants, FilesysIO fio,
        scope TokenStream tstream, MutantIdGeneratorConfig idGenConf) {
    auto result = new CodeMutantsResult(mutants.lang, fio, idGenConf);
    result.put(mutants.files);

    foreach (f; mutants.files.map!(a => a.path).array.sort) {
        foreach (mp; mutants.getMutationPoints(f).filter!(a => !a.kind.empty)) {
            // use this to easily find zero length mutants.
            // note though that it can't always be active because it has
            // some false positives such as dccBomb
            //if (mp.point.offset.begin == mp.point.offset.end) {
            //    logger.warningf("Malformed mutant (begin == end), dropping. %s %s %s %s",
            //            mp.kind, mp.point.offset, mp.point.sloc, f);
            //}

            if (mp.point.offset.begin > mp.point.offset.end) {
                log.warningf("Malformed mutant (begin > end), dropping. %s %s %s %s",
                        mp.kind, mp.point.offset, mp.point.sloc, f);
            } else {
                result.updateContentWindow(mp.point.context);
                result.changeActiveFile(f, tstream);
                result.put(f, mp.point.offset, mp.point.sloc, mp.kind);
            }
        }
    }

    // logger.info(result);

    return result;
}

class MutantsResult {
    import dextool.plugin.mutate.backend.type : Checksum;
    import my.set;

    static struct MutationPoint {
        Offset offset;
        SourceLocRange sloc;
        Offset context;

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
            formattedWrite!"[%s:%s-%s:%s]:[%s:%s][%s:%s]"(w, sloc.begin.line,
                    sloc.begin.column, sloc.end.line, sloc.end.column,
                    offset.begin, offset.end, context.begin, context.end);
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
            log.warningf("%s: %s", absp, e.msg);
        }
    }

    private void put(AbsolutePath p, MutationPoint mp, Mutation.Kind kind) @safe {
        if (kind !in kinds)
            return;

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
    import my.hash : Checksum64, BuildChecksum64, toBytes, toChecksum64;
    import dextool.plugin.mutate.backend.type : CodeMutant, CodeChecksum, Mutation, Checksum;
    import dextool.plugin.mutate.backend.analyze.id_factory : MutantIdFactory;

    const Language lang;
    Tuple!(AbsolutePath, "path", Checksum, "cs")[] files;

    static struct MutationPoint {
        CodeMutant mutant;
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

        /// Current filename that the id factory is initialized with.
        AbsolutePath idFileName;
        MutantIdFactory idFactory;

        /// Tokens of the current file that idFactory is configured for.
        Token[] tokens;

        Offset contentWindow;
    }

    this(Language lang, FilesysIO fio, MutantIdGeneratorConfig idGenConf) {
        this.lang = lang;
        this.fio = fio;
        this.idFactory = () {
            import dextool.plugin.mutate.backend.analyze.id_factory : StrictImpl, RelaxedImpl;

            final switch (idGenConf) {
            case MutantIdGeneratorConfig.strict:
                return cast(MutantIdFactory) new StrictImpl;
            case MutantIdGeneratorConfig.relaxed:
                return cast(MutantIdFactory) new RelaxedImpl;
            }
        }();
    }

    /// Expected to be updated for each new mutation point.
    void updateContentWindow(const Offset v) {
        contentWindow = v;
    }

    private void changeActiveFile(AbsolutePath p, scope TokenStream tstream) @trusted {
        if (p == idFileName)
            return;

        idFileName = p;
        tokens = () @trusted { return tstream.getFilteredTokens(p); }();
        idFactory.changeFile(fio.toRelativeRoot(p), tokens);
    }

    private void put(typeof(MutantsResult.files) mfiles) {
        files = mfiles;
        foreach (f; files) {
            csFiles[f.path] = f.cs;
            points[f.path] = (MutationPoint[]).init;
        }
    }

    // the mutation points must be added in sorted order by their offset
    private void put(AbsolutePath p, Offset offset, SourceLocRange sloc, Mutation.Kind[] kinds) @safe {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

        idFactory.update(contentWindow, offset, tokens);

        auto fin = fio.makeInput(p);
        auto muts = appender!(MutationPoint[])();
        foreach (kind; kinds) {
            scope txt = makeMutationText(fin, offset, kind, lang);
            auto cm = idFactory.make(Mutation(kind), txt.rawMutation);
            muts.put(MutationPoint(cm, offset, sloc));
        }
        points[p] ~= muts.data;
    }

    override string toString() @safe {
        import std.range : put;

        auto w = appender!string();

        formattedWrite(w, "Files:\n");
        foreach (f; files) {
            formattedWrite!"%s %s\n"(w, f.path, f.cs);

            foreach (mp; points[f.path]) {
                formattedWrite!"  %s->%s\n"(w, mp, mp.mutant);
            }
        }

        return w.data;
    }
}

private:

struct ContextData {
    Offset pos;
    AbsolutePath path;

    bool isInsideScope(Location l) {
        return l.file == path && l.interval.begin >= pos.begin && l.interval.end <= pos.end;
    }
}

class FindRootVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutations, DcrInfo;
    import dextool.plugin.mutate.backend.mutation_type.sdl : stmtDelMutations;
    import my.container.vector;

    Ast* ast;
    MutantsResult result;
    FilesysIO fio;
    ValidateLoc vloc;

    private {
        uint depth;
        Stack!Node nstack;
        Vector!ContextData context;

        ulong dontVisitNodeId;
    }

    alias visit = DepthFirstVisitor.visit;

    this(Ast* ast, FilesysIO fio, ValidateLoc vloc, Mutation.Kind[] kinds) scope {
        this.ast = ast;
        this.fio = fio;
        this.vloc = vloc;
        result = new MutantsResult(ast.lang, fio, vloc, kinds);

        // by adding the locations here the rest of the visitor do not have to
        // be concerned about adding files.
        foreach (ref l; ast.locs.byValue) {
            result.put(l.file);
        }
    }

    override void visitPush(Node n) {
        ++depth;
        nstack.put(n, depth);
    }

    override void visitPop(Node n) {
        nstack.pop;
        --depth;
    }

    override void visit(TranslationUnit n) nothrow {
        try {
            const l = ast.location(n);
            if (vloc.isInsideOutputDir(l.file)) {
                context.put(getContextOfFile(l.file));
                accept(n, this);
                context.popBack;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    override void visit(Function n) {
        if (!n.children.empty)
            subVisit(n);
    }

    override void visit(Poison n) {
        if (n.context)
            subVisit(n);
    }

    override void visit(DeclRef n) {
        if (n.to !is null)
            dontVisitNodeId = n.to.id;
        accept(n, this);
    }

    override void visit(VarDecl n) {
        const l = ast.location(n);
        if (!vloc.isInsideOutputDir(l.file))
            return;

        auto c = () {
            if (l.file == context.back.path)
                return context.back;
            return getContextOfFile(l.file);
        }();
        logger.tracef("Start analyze of %s:%s with context %s", n.kind, n.id, c);
        scope visitor = new MutantVisitor(ast, fio, vloc, result, c, depth, nstack);
        visitor.start(n);

        accept(n, this);
    }

    void subVisit(T)(T n) {
        if (n.id == dontVisitNodeId) {
            dontVisitNodeId = 0;
            return;
        }

        const l = ast.location(n);
        if (!vloc.isInsideOutputDir(l.file))
            return;

        context.put(ContextData(l.interval, l.file));
        logger.tracef("Start analyze of %s:%s with context %s", n.kind, n.id, l);
        scope visitor = new MutantVisitor(ast, fio, vloc, result, context.back, depth, nstack);
        visitor.start(n);
        accept(n, this);
        context.popBack;
    }

    ContextData getContextOfFile(AbsolutePath file) {
        auto fin = fio.makeInput(file);
        auto offset = Offset(0, cast(uint) fin.content.length);
        return ContextData(offset, file);
    }
}

class MutantVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutations, DcrInfo;
    import dextool.plugin.mutate.backend.mutation_type.sdl : stmtDelMutations;

    Ast* ast;
    MutantsResult result;
    FilesysIO fio;
    ValidateLoc vloc;

    private {
        uint depth;
        Stack!Node nstack;

        ContextData context;
    }

    alias visit = DepthFirstVisitor.visit;

    this(Ast* ast, FilesysIO fio, ValidateLoc vloc, MutantsResult result,
            ContextData context, uint depth, Stack!Node nstack) scope {
        this.ast = ast;
        this.fio = fio;
        this.vloc = vloc;
        this.result = result;
        this.context = context;
        this.depth = depth;
        this.nstack = nstack;
    }

    override void visitPush(Node n) {
        ++depth;
        nstack.put(n, depth);
    }

    override void visitPop(Node n) {
        nstack.pop;
        --depth;
    }

    bool preconditionVisit(T)(T n) {
        const auto loc = ast.location(n);
        const auto res = context.isInsideScope(loc);
        if (!res)
            logger.tracef("Stop analyze of %s:%s (%s) because outside scope %s",
                    n.kind, n.id, loc, context);
        return res;
    }

    /// Returns: the closest function from the current node.
    Function getClosestFunc() {
        return cast(Function) match!((a) {
            if (a.data.kind == Kind.Function)
                return a.data;
            return null;
        })(nstack, Direction.topToBottom);
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

    /// Returns: if the parent function is void returning.
    bool isParentVoidFunc() {
        auto f = getClosestFunc;
        if (f is null)
            return true;
        return f.return_ is null;
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
            result.put(loc.file, MutantsResult.MutationPoint(loc.interval,
                    loc.sloc, context.pos), kind);
        }
    }

    void start(NodeT)(NodeT n) scope @trusted {
        accept(n, this);
    }

    override void visit(Function n) {
    }

    override void visit(Constructor n) {
        accept(n, this);
    }

    override void visit(Expr n) {
        auto loc = ast.location(n);

        if (isParentBoolFunc && isParent(Kind.Return) && !isParent(Kind.Call)) {
            put(loc, dcrMutations(DcrInfo(n.kind, ast.type(n))), n.blacklist);
        }

        accept(n, this);
    }

    override void visit(FieldRef n) {
        accept(n, this);
    }

    override void visit(FieldDecl n) {
        accept(n, this);
    }

    override void visit(VarRef n) {
        accept(n, this);
    }

    override void visit(VarDecl n) {
        accept(n, this);
    }

    override void visit(Literal n) {
        import dextool.plugin.mutate.backend.mutation_type.cr;

        put(ast.location(n), crMutations(n.kind), n.blacklist);
        accept(n, this);
    }

    override void visit(FloatLiteral n) {
        import dextool.plugin.mutate.backend.mutation_type.cr;

        put(ast.location(n), crMutations(n.kind), n.blacklist);
        accept(n, this);
    }

    override void visit(Block n) {
        if (n.children.empty)
            return;
        sdlBlock(n, ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(Loop n) {
        if (n.children.empty)
            return;
        sdlBlock(n, ast.location(n), stmtDelMutations(n.kind));
        accept(n, this);
    }

    override void visit(BranchBundle n) {
        accept(n, this);
    }

    override void visit(Call n) {
        // the check isParent..:
        // e.g. a C++ class constructor calls a members constructor in its
        // initialization list.
        // TODO: is this needed? I do not think so considering the rest of the
        // code.

        if (isParent(Kind.Function) && !isParent(Kind.Return) && isDirectParent(Kind.Block)) {
            // the check for Return blocks all SDL when an exception is thrown.
            //
            // the check isDirectParent(Kind.Block) is to only delete function
            // or method calls that are at the root of a chain of calls in the
            // AST.
            //
            // a bit restricive to be begin with to only delete void returning
            // functions. Extend it in the future when it can "see" that the
            // return value is discarded.
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }

        if (isDirectParent(Kind.Return) && isParentBoolFunc) {
            put(ast.location(n), dcrMutations(DcrInfo(n.kind, ast.type(n))), n.blacklist);
        }

        // should call visitOp
        accept(n, this);
    }

    override void visit(Return n) {
        accept(n, this);
    }

    override void visit(BinaryOp n) {
        if (isDirectParent(Kind.Block)) {
            put(ast.location(n), stmtDelMutations(n.kind), n.blacklist);
        }
        accept(n, this);
    }

    override void visit(Poison n) {
        if (!n.context)
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

    override void visit(OpCmp n) {
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
            // must analyze the n node because it is the one holding the
            // children which is the whole hierarchy of nodes. the inside is
            // "just" the inside of the block to delete.
            sdlBlock(n, ast.location(n.inside), stmtDelMutations(n.kind));
        }

        accept(n, this);
    }

    private void visitUnaryOp(T)(T n) {
        auto loc = ast.location(n);

        Mutation.Kind[] expr;

        {
            import dextool.plugin.mutate.backend.mutation_type.uoi;

            expr ~= uoiMutations(n.kind);
        }
        if (isDirectParent(Kind.Block)) {
            expr ~= stmtDelMutations(n.kind);
        }

        put(loc, expr, n.blacklist);
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

            auto m = aorMutations(AorInfo(n.kind, ast.type(n.lhs),
                    ast.type(n.rhs), n.operator.isOverloaded));
            op ~= m.op ~ m.simple;
            lhs ~= m.lhs;
            rhs ~= m.rhs;
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
            put(Location(locOp.file, offset, SourceLocRange(locExpr.sloc.begin,
                    locOp.sloc.end)), lhs, n.lhs.blacklist);
        }
        if (n.rhs !is null && locOp.interval.begin < locExpr.interval.end) {
            auto offset = Interval(locOp.interval.begin, locExpr.interval.end);
            put(Location(locOp.file, offset, SourceLocRange(locOp.sloc.begin,
                    locExpr.sloc.end)), rhs, n.rhs.blacklist);
        }
    }

    private void sdlBlock(T)(T n, Location delLoc, Mutation.Kind[] op) @trusted {
        scope sdlAnalyze = new DeleteBlockVisitor(ast, delLoc);
        sdlAnalyze.startVisit(n);
        const isVoid = isParentVoidFunc;
        if (sdlAnalyze.canRemove && (isVoid || (!isVoid && !sdlAnalyze.hasReturn)))
            put(delLoc, op, n.blacklist);
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
    import dextool.plugin.mutate.backend.analyze.utility : isInsideRootMixin;

    Ast* ast;

    private {
        bool hasInnerNodes;
        Location root;
    }

    bool hasReturn;

    alias visit = DepthFirstVisitor.visit;
    mixin isInsideRootMixin!root;

    this(Ast* ast, Location root) {
        this.ast = ast;
        this.root = root;
    }

    // if the analyzer has determined that this node in the tree can be removed
    // with SDL. Note though that it doesn't know anything about the parent
    // node.
    bool canRemove() {
        return hasInnerNodes;
    }

    /// The node to start analysis from.
    void startVisit(Node n) {
        hasInnerNodes = !n.children.empty;
        if (hasInnerNodes)
            visit(n);
    }

    override void visit(Return n) {
        if (isInsideRoot(ast.location(n)))
            hasReturn = true;
    }
}
