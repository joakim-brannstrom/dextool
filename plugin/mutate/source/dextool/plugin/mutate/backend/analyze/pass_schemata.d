/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.pass_schemata;

import logger = std.experimental.logger;
import std.algorithm : among, map, sort, filter, canFind, copy, uniq, any, sum, joiner;
import std.array : appender, empty, array, Appender;
import std.conv : to;
import std.exception : collectException;
import std.format : formattedWrite, format;
import std.meta : AliasSeq;
import std.range : ElementType, only;
import std.traits : EnumMembers;
import std.typecons : tuple, Tuple, scoped;
import std.sumtype;

import my.container.vector : vector, Vector;
import my.optional;
import my.set;

static import colorlog;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast : Interval, Location;
import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ;
import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.internal;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.database.type : SchemataFragment;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset,
    Mutation, SourceLocRange, CodeMutant, SchemataChecksum, Checksum;

import dextool.plugin.mutate.backend.analyze.ast;
import dextool.plugin.mutate.backend.analyze.pass_mutant : CodeMutantsResult;

alias log = colorlog.log!"analyze.pass_schema";

shared static this() {
    colorlog.make!(colorlog.SimpleLogger)(logger.LogLevel.info, "analyze.pass_schema");
}

// constant defined by the schemata that test_mutant uses too
/// The function that a mutant reads to see if it should activate.
immutable schemataMutantIdentifier = "dextool_get_mutid()";
/// The environment variable that is read to set the current active mutant.
immutable schemataMutantEnvKey = "DEXTOOL_MUTID";

/// Translate a mutation AST to a schemata.
SchemataResult toSchemata(scope Ast* ast, FilesysIO fio, CodeMutantsResult cresult, SchemaQ sq) @trusted {
    auto rval = new SchemataResult;
    auto index = new CodeMutantIndex(cresult);

    final switch (ast.lang) {
    case Language.c:
        goto case;
    case Language.assumeCpp:
        goto case;
    case Language.cpp:
        scope visitor = new CppRootVisitor(ast, index, sq, fio, rval);
        ast.accept(visitor);
        break;
    }

    return rval;
}

@safe:

/** Converts a checksum to a 32-bit ID that can be used to activate a mutant.
 *
 * Guaranteed that zero is never used. It is reserved for no mutant.
 */
uint checksumToId(Checksum cs) @safe pure nothrow @nogc {
    return checksumToId(cs.c0);
}

uint checksumToId(ulong cs) @safe pure nothrow @nogc {
    uint ubit = cast(uint)(cs >> 32);
    uint lbit = cast(uint)(0x00000000ffffffff & cs);
    uint h = ubit ^ lbit;

    return h == 0 ? 1 : h;
}

/// Language generic schemata result.
class SchemataResult {
    static struct Fragment {
        Offset offset;
        const(ubyte)[] text;
        CodeMutant[] mutants;
    }

    static struct Fragments {
        // TODO: change to using appender
        Fragment[] fragments;
    }

    private {
        Fragments[AbsolutePath] fragments;
    }

    /// Returns: all fragments containing mutants per file.
    Fragments[AbsolutePath] getFragments() @safe {
        return fragments;
    }

    /// Assuming that all fragments for a file should be merged to one huge.
    private void putFragment(AbsolutePath file, Fragment sf) {
        fragments.update(file, () => Fragments([sf]), (ref Fragments a) {
            a.fragments ~= sf;
        });
    }

    override string toString() @safe {
        import std.range : put;
        import std.utf : byUTF;

        auto w = appender!string();

        void toBuf(Fragments s) {
            foreach (f; s.fragments) {
                formattedWrite(w, "  %s: %s\n", f.offset,
                        (cast(const(char)[]) f.text).byUTF!(const(char)));
                formattedWrite(w, "%(    %s\n%)\n", f.mutants);
            }
        }

        foreach (k; fragments.byKey.array.sort) {
            try {
                formattedWrite(w, "%s:\n", k);
                toBuf(fragments[k]);
            } catch (Exception e) {
            }
        }

        return w.data;
    }
}

private:

// An index over the mutants and the interval they apply for.
class CodeMutantIndex {
    CodeMutant[][Offset][AbsolutePath] index;

    this(CodeMutantsResult result) {
        foreach (p; result.points.byKeyValue) {
            CodeMutant[][Offset] e;
            foreach (mp; p.value) {
                if (auto v = mp.offset in e) {
                    (*v) ~= mp.mutant;
                } else {
                    e[mp.offset] = [mp.mutant];
                }
            }
            index[p.key] = e;
        }
    }

    CodeMutant[] get(AbsolutePath file, Offset o) {
        if (auto v = file in index) {
            if (auto w = o in *v) {
                return *w;
            }
        }
        return null;
    }
}

/// Build a fragment for a schema.
struct FragmentBuilder {
    static struct Part {
        CodeMutant mutant;
        // ID used to activate the mutant.
        ulong id;
        const(ubyte)[] mod;
    }

    SchemaQ sq;

    Appender!(Part[]) parts;
    /// Length of the fragments in parts.
    size_t partsLn;

    const(ubyte)[] original;
    Path file;
    Location loc;
    Interval interval;

    void start(Path file, Location l, const(ubyte)[] original) {
        parts.clear;
        this.file = file;
        this.loc = l;
        this.interval = l.interval;
        this.original = original;
    }

    void put(CodeMutant mutant, ulong id, const(ubyte)[] mods) {
        // happens sometimes that a very large functions with an extrem amount
        // of mutants in it blow up the number of fragments. This is to limit
        // it to a reasonable overall fragment size. Without this the memory on
        // a 64Gbyte computer will run out.
        enum TenMb = 1024 * 1024 * 10;
        if (partsLn < TenMb) {
            parts.put(Part(mutant, id, mods));
        } else {
            log.tracef("Total fragment size %s > %s. Discarding", partsLn, TenMb);
        }
        partsLn += mods.length;
    }

    void put(T...)(CodeMutant mutant, ulong id, auto ref T mods) {
        auto app = appender!(const(ubyte)[])();
        foreach (a; mods) {
            app.put(a);
        }
        this.put(mutant, id, app.data);
    }

    SchemataResult.Fragment[] finalize() {
        auto rval = appender!(typeof(return))();
        Set!ulong mutantIds;
        auto m = appender!(CodeMutant[])();
        auto schema = BlockChain(original);
        void makeFragment() {
            if (!mutantIds.empty) {
                rval.put(SchemataResult.Fragment(loc.interval, schema.generate, m.data.dup));
                m.clear;
                schema = BlockChain(original);
                mutantIds = typeof(mutantIds).init;
            }
        }

        void useFragment(Part p) {
            schema.put(p.id, p.mod);
            m.put(p.mutant);
            mutantIds.add(p.id);
        }

        auto queue = parts.data[];
        typeof(queue) repeat;
        bool popQueue() {
            queue = queue[0 .. $ - 1];
            const rval = queue.empty && !repeat.empty;
            if (queue.empty) {
                queue = repeat;
                repeat = null;
            }
            return rval;
        }

        while (!queue.empty) {
            auto p = queue[$ - 1];
            const forceMake = popQueue;

            if (!sq.use(file, p.mutant.mut.kind, 0.01)) {
                // do not add any fragments that are almost certain to fail.
                // but keep it at 1 because then they will be randomly tested
                // for succes now and then.
                makeFragment;
                useFragment(p);
                makeFragment;
            } else if (sq.isZero(file, p.mutant.mut.kind)) {
                // isolate always failing fragments.
                makeFragment;
                useFragment(p);
                makeFragment;
            } else if (mutantIds.length > 0 && schema.length > 100000) {
                // too large fragments blow up the compilation time. Must check that
                // there is at least one mutant in the fragment because
                // otherwise we could end up with fragments that only contain
                // the original. There are namely function bodies that are
                // very large such as the main function in "grep".
                // The number 100k is based on running on
                // examples/game_tutorial and observe how large the scheman are
                // together with how many mutants are left after the scheman
                // have executed. With a limit of:
                // 10k result in 53 scheman and 233 mutants left after executed.
                // 100k result in 8 scheman and 148 mutants left after executed.
                // 1 milj results in 4 shceman and 147 mutants left after executed.
                // thus 100k is chosen.
                makeFragment;
                repeat ~= p;
            } else if (p.id in mutantIds) {
                // the ID cannot be duplicated because then two mutants would
                // be activated at the same time.
                repeat ~= p;
            } else {
                useFragment(p);
            }

            if (forceMake)
                makeFragment;
        }

        makeFragment;

        return rval.data;
    }
}

struct MutantHelper {
    this(ref FragmentBuilder fragment, Interval offs) {
        pre = () {
            if (offs.begin <= fragment.interval.begin)
                return null;
            const d = offs.begin - fragment.interval.begin;
            if (d > fragment.original.length)
                return fragment.original;
            return fragment.original[0 .. d];
        }();

        post = () {
            if (offs.end <= fragment.interval.begin)
                return null;
            const d = offs.end - fragment.interval.begin;
            if (d > fragment.original.length)
                return fragment.original;
            return fragment.original[d .. $];
        }();
    }

    const(ubyte)[] pre;
    const(ubyte)[] post;
}

class CppRootVisitor : DepthFirstVisitor {
    Ast* ast;
    CodeMutantIndex index;
    SchemataResult result;
    FilesysIO fio;
    SchemaQ sq;

    alias visit = DepthFirstVisitor.visit;

    this(Ast* ast, CodeMutantIndex index, SchemaQ sq, FilesysIO fio, SchemataResult result)
    in (ast !is null) {
        this.ast = ast;
        this.index = index;
        this.fio = fio;
        this.result = result;
        this.sq = sq;
    }

    override void visit(Function n) @trusted {
        scope funcVisitor = new CppSchemataVisitor(ast, index, sq, fio, result);
        funcVisitor.startVisit(n);
        accept(n, this);
    }
}

mixin template isInsideRoot(alias fragmentRoot) {
    bool isInsideRoot(Location l) {
        // can occur when a Call refer to an inline function.
        return fragmentRoot.file == l.file && fragmentRoot.interval.begin <= l.interval.begin
            && l.interval.end <= fragmentRoot.interval.end;
    }
}

class CppSchemataVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

    Ast* ast;
    CodeMutantIndex index;
    SchemataResult result;
    FilesysIO fio;

    Location fragmentRoot;

    FragmentBuilder fragment;

    Stack!(Node) nstack;
    uint depth;

    alias visit = DepthFirstVisitor.visit;

    this(Ast* ast, CodeMutantIndex index, SchemaQ sq, FilesysIO fio, SchemataResult result)
    in (ast !is null) {
        this.ast = ast;
        this.index = index;
        this.fio = fio;
        this.result = result;
        this.fragment.sq = sq;
    }

    /// Returns: if the previous nodes is of kind `k`.
    bool isDirectParent(Args...)(auto ref Args kinds) {
        if (nstack.empty)
            return false;
        return nstack.back.kind.among(kinds) != 0;
    }

    mixin isInsideRoot!fragmentRoot;

    void startVisit(Function n) @trusted {
        auto firstBlock = () {
            foreach (c; n.children.filter!(a => a.kind == Kind.Block))
                return c;
            return null;
        }();
        if (firstBlock is null)
            return;
        auto loc = ast.location(firstBlock);
        if (loc.interval.isZero)
            return;
        fragmentRoot = loc;

        fragment.start(fio.toRelativeRoot(loc.file), loc, () {
            auto fin = fio.makeInput(loc.file);
            // must be at least length 1 because ChainT look at the last
            // value
            if (fragmentRoot.interval.begin >= fragmentRoot.interval.end)
                return " ".rewrite;
            return fin.content[fragmentRoot.interval.begin .. fragmentRoot.interval.end];
        }());

        visit(firstBlock);

        foreach (f; fragment.finalize) {
            result.putFragment(fragmentRoot.file, f);
        }
    }

    override void visitPush(Node n) {
        nstack.put(n, ++depth);
    }

    override void visitPop(Node n) {
        nstack.pop;
        --depth;
    }

    override void visit(Function n) @trusted {
        // block visit
    }

    override void visit(Expr n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(Block n) {
        visitBlock(n, true);
        accept(n, this);
    }

    override void visit(Loop n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(Call n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(Return n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(BinaryOp n) {
        // these are operators such as x += 2
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssign n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssignAdd n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssignAndBitwise n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssignDiv n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssignMod n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssignMul n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssignOrBitwise n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpAssignSub n) {
        visitBlock(n);
        accept(n, this);
    }

    override void visit(OpNegate n) {
        visitUnaryOp(n);
        accept(n, this);
    }

    override void visit(OpAndBitwise n) {
        visitBinaryOp(n);
    }

    override void visit(OpAnd n) {
        visitBinaryOp(n);
    }

    override void visit(OpOrBitwise n) {
        visitBinaryOp(n);
    }

    override void visit(OpOr n) {
        visitBinaryOp(n);
    }

    override void visit(OpLess n) {
        visitBinaryOp(n);
    }

    override void visit(OpLessEq n) {
        visitBinaryOp(n);
    }

    override void visit(OpGreater n) {
        visitBinaryOp(n);
    }

    override void visit(OpGreaterEq n) {
        visitBinaryOp(n);
    }

    override void visit(OpEqual n) {
        visitBinaryOp(n);
    }

    override void visit(OpNotEqual n) {
        visitBinaryOp(n);
    }

    override void visit(OpAdd n) {
        visitBinaryOp(n);
    }

    override void visit(OpSub n) {
        visitBinaryOp(n);
    }

    override void visit(OpMul n) {
        visitBinaryOp(n);
    }

    override void visit(OpMod n) {
        visitBinaryOp(n);
    }

    override void visit(OpDiv n) {
        visitBinaryOp(n);
    }

    override void visit(Condition n) {
        visitCondition(n);
        accept(n, this);
    }

    override void visit(BranchBundle n) @trusted {
        visitBlock(n, true);
        accept(n, this);
    }

    override void visit(Branch n) {
        if (n.inside !is null) {
            visitBlock(n.inside, true);
        }
        accept(n, this);
    }

    private void visitCondition(T)(T n) @trusted {
        if (n.schemaBlacklist)
            return;

        // The schematas from the code below are only needed for e.g. function
        // calls such as if (fn())...

        auto loc = ast.location(n);
        auto mutants = index.get(loc.file, loc.interval);

        if (loc.interval.isZero || mutants.empty || !isInsideRoot(loc))
            return;

        auto fin = fio.makeInput(loc.file);
        auto content = fin.content[loc.interval.begin .. loc.interval.end];
        if (content.empty)
            return;

        auto helper = MutantHelper(fragment, loc.interval);

        foreach (mutant; mutants) {
            fragment.put(mutant, mutant.id.c0, helper.pre,
                    makeMutation(mutant.mut.kind, ast.lang).mutate(
                        fin.content[loc.interval.begin .. loc.interval.end]), helper.post);
        }
    }

    private void visitBlock(T)(T n, bool requireSyntaxBlock = false) {
        if (n.schemaBlacklist)
            return;

        auto loc = ast.location(n);
        auto offs = loc.interval;
        auto mutants = index.get(loc.file, offs);

        if (loc.interval.isZero || mutants.empty || !isInsideRoot(loc))
            return;

        auto fin = fio.makeInput(loc.file);

        auto helper = MutantHelper(fragment, loc.interval);

        auto content = () {
            // this is just defensive code. not proven to be a problem.
            if (any!(a => a >= fin.content.length)(only(offs.begin, offs.end)))
                return " ".rewrite;
            return fin.content[offs.begin .. offs.end];
        }();

        foreach (mutant; mutants) {
            auto mut = () {
                auto mut = makeMutation(mutant.mut.kind, ast.lang).mutate(content);
                if (mut.empty && requireSyntaxBlock)
                    return "{}".rewrite;
                return mut;
            }();
            fragment.put(mutant, mutant.id.c0, helper.pre, mut, helper.post);
        }
    }

    private void visitUnaryOp(T)(T n) {
        if (n.schemaBlacklist || n.operator.schemaBlacklist)
            return;

        auto loc = ast.location(n);
        auto mutants = index.get(loc.file, loc.interval);

        if (loc.interval.isZero || mutants.empty || !isInsideRoot(loc))
            return;

        auto fin = fio.makeInput(loc.file);
        auto helper = MutantHelper(fragment, loc.interval);

        foreach (mutant; mutants) {
            fragment.put(mutant, mutant.id.c0, helper.pre,
                    makeMutation(mutant.mut.kind, ast.lang).mutate(
                        fin.content[loc.interval.begin .. loc.interval.end]), helper.post);
        }
    }

    private void visitBinaryOp(T)(T n) @trusted {
        if (!isInsideRoot(ast.location(n)))
            return;

        try {
            scope v = new BinaryOpVisitor(ast, &index, fio, &fragment);
            v.startVisit(n);
        } catch (Exception e) {
        }
        accept(n, this);
    }
}

class BinaryOpVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

    Ast* ast;
    CodeMutantIndex* index;
    FragmentBuilder* fragment;
    FilesysIO fio;

    // the root of the expression that is being mutated
    Location rootLoc;
    Interval root;

    /// Content of the file that contains the mutant.
    const(ubyte)[] content;

    alias visit = DepthFirstVisitor.visit;

    this(Ast* ast, CodeMutantIndex* index, FilesysIO fio, FragmentBuilder* fragment) {
        this.ast = ast;
        this.index = index;
        this.fio = fio;
        this.fragment = fragment;
    }

    void startVisit(T)(T n) {
        rootLoc = ast.location(n);
        root = rootLoc.interval;

        if (root.begin >= root.end) {
            // can happen for C macros
            return;
        }

        content = fio.makeInput(rootLoc.file).content;

        if (content.empty)
            return;

        visit(n);
    }

    mixin isInsideRoot!rootLoc;

    override void visit(OpAndBitwise n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpAnd n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpOrBitwise n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpOr n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpLess n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpLessEq n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpGreater n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpGreaterEq n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpEqual n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpNotEqual n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpAdd n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpSub n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpMul n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpMod n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    override void visit(OpDiv n) {
        visitBinaryOp(n);
        accept(n, this);
    }

    private void visitBinaryOp(T)(T n) {
        if (n.schemaBlacklist || n.operator.schemaBlacklist)
            return;

        auto locExpr = ast.location(n);
        auto locOp = ast.location(n.operator);

        if (locExpr.interval.isZero || locOp.interval.isZero
                || !isInsideRoot(locExpr) || !isInsideRoot(locOp))
            return;

        auto left = contentOrNull(root.begin, locExpr.interval.begin, content);
        auto right = contentOrNull(locExpr.interval.end, root.end, content);

        auto opMutants = index.get(locOp.file, locOp.interval);

        auto exprMutants = index.get(locOp.file, locExpr.interval);

        auto offsLhs = Offset(locExpr.interval.begin, locOp.interval.end);
        auto lhsMutants = index.get(locOp.file, offsLhs);

        auto offsRhs = Offset(locOp.interval.begin, locExpr.interval.end);
        auto rhsMutants = index.get(locOp.file, offsRhs);

        if (opMutants.empty && lhsMutants.empty && rhsMutants.empty && exprMutants.empty)
            return;

        if (locExpr.interval.begin < locOp.interval.begin
                && locOp.interval.end < locExpr.interval.end) {
            auto helper = MutantHelper(*fragment, locOp.interval);

            foreach (mutant; opMutants) {
                // dfmt off
                fragment.put(mutant, mutant.id.c0,
                        helper.pre,
                        makeMutation(mutant.mut.kind, ast.lang).mutate(content[locOp.interval.begin .. locOp.interval.end]),
                        helper.post
                        );
                // dfmt on
            }
        }

        auto helper = MutantHelper(*fragment, locExpr.interval);

        if (offsLhs.end < locExpr.interval.end) {
            foreach (mutant; lhsMutants) {
                // dfmt off
                fragment.put(mutant, mutant.id.c0,
                    helper.pre,
                    left,
                    makeMutation(mutant.mut.kind, ast.lang).mutate(content[offsLhs.begin .. offsLhs.end]),
                    content[offsLhs.end .. locExpr.interval.end],
                    right,
                    helper.post
                    );
                // dfmt on
            }
        }

        if (locExpr.interval.begin < offsRhs.begin) {
            foreach (mutant; rhsMutants) {
                // dfmt off
                fragment.put(mutant, mutant.id.c0,
                    helper.pre,
                    left,
                    content[locExpr.interval.begin .. offsRhs.begin],
                    makeMutation(mutant.mut.kind, ast.lang).mutate(content[offsRhs.begin .. offsRhs.end]),
                    right,
                    helper.post
                    );
                // dfmt on
            }
        }

        foreach (mutant; exprMutants) {
            // dfmt off
            fragment.put(mutant, mutant.id.c0,
                helper.pre,
                left,
                makeMutation(mutant.mut.kind, ast.lang).mutate(content[locExpr.interval.begin .. locExpr.interval.end]),
                right,
                helper.post
                );
            // dfmt on
        }
    }
}

const(ubyte)[] rewrite(string s) {
    return cast(const(ubyte)[]) s;
}

SchemataResult.Fragment rewrite(Location loc, string s, CodeMutant[] mutants) {
    return rewrite(loc, cast(const(ubyte)[]) s, mutants);
}

/// Create a fragment that rewrite a source code location to `s`.
SchemataResult.Fragment rewrite(Location loc, const(ubyte)[] s, CodeMutant[] mutants) {
    return SchemataResult.Fragment(loc.interval, s, mutants);
}

/** A schemata is uniquely identified by the mutants that it contains.
 *
 * The order of the mutants are irrelevant because they are always sorted by
 * their value before the checksum is calculated.
 *
 */
SchemataChecksum toSchemataChecksum(CodeMutant[] mutants) {
    import dextool.plugin.mutate.backend.utility : BuildChecksum, toChecksum, toBytes;
    import dextool.utility : dextoolBinaryId;

    BuildChecksum h;
    // this make sure that schematas for a new version av always added to the
    // database.
    h.put(dextoolBinaryId.toBytes);
    foreach (a; mutants.sort!((a, b) => a.id.value < b.id.value)
            .map!(a => a.id.value)) {
        h.put(a.c0.toBytes);
    }

    return SchemataChecksum(toChecksum(h));
}

/** Accumulate block modification of the program to then generate a
 * if-statement chain that activates them if the mutant is set. The last one is
 * the original.
 *
 * A id can only be added once to the chain. This ensure that there are no
 * duplications. This can happen when e.g. adding rorFalse and dcrFalse to an
 * expression group. They both result in the same source code mutation thus
 * only one of them is actually needed. This deduplications this case.
 *
 * This assume that id `0` means "no mutant". The generated schema has as the
 * first branch id `0` on the assumption that this is the hot path/common case
 * and the branch predictor assume that the first branch is taken. All schemas
 * also have an else which contains the same code. This is just a defensive
 * measure in case something funky happens. Maybe it should be an assert? Who
 * knows but for now it is a duplicated because that will always work on all
 * platforms.
 */
struct BlockChain {
    alias Mutant = Tuple!(ulong, "id", const(ubyte)[], "value");
    Appender!(Mutant[]) mutants;
    const(ubyte)[] original;
    size_t length;

    this(const(ubyte)[] original) {
        this.original = original;
        this.length += original.length;
    }

    bool empty() @safe pure nothrow const @nogc {
        return mutants.data.empty;
    }

    /// Returns: `value`
    const(ubyte)[] put(ulong id, const(ubyte)[] value) {
        // 100 is a magic number that assume that each fragment also result in
        //     ~100 characters extra "overhead" by somewhat manually
        //     calculating what is in `generate`.
        length += value.length + 100;
        mutants.put(Mutant(id, value));
        return value;
    }

    /// Returns: the merge of `values`
    const(ubyte)[] put(T...)(ulong id, auto ref T values) {
        auto app = appender!(const(ubyte)[])();
        static foreach (a; values) {
            app.put(a);
        }
        return this.put(id, app.data);
    }

    /// Returns: the generated chain that can replace the original expression.
    const(ubyte)[] generate() {
        if (mutants.data.empty)
            return null;

        auto app = appender!(const(ubyte)[])();

        bool isFirst = true;
        foreach (const mutant; mutants.data) {
            if (isFirst) {
                app.put("if (unlikely(".rewrite);
                isFirst = false;
            } else {
                app.put(" else if (unlikely(".rewrite);
            }

            app.put(format!"%s == "(schemataMutantIdentifier).rewrite);
            app.put(mutant.id.checksumToId.to!string.rewrite);
            app.put("u".rewrite);
            app.put(")) {".rewrite);

            app.put(mutant.value);
            if (!mutant.value.empty && mutant.value[$ - 1] != cast(ubyte) ';')
                app.put(";".rewrite);

            app.put("} ".rewrite);
        }

        app.put(" else {".rewrite);
        app.put(original);
        if (!original.empty && original[$ - 1] != cast(ubyte) ';')
            app.put(";".rewrite);
        app.put("}".rewrite);

        return app.data;
    }
}

auto contentOrNull(uint begin, uint end, const(ubyte)[] content) {
    if (begin >= end || end > content.length)
        return null;
    return content[begin .. end];
}
