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
import std.algorithm : among, map, sort, filter, canFind, copy, uniq, any;
import std.array : appender, empty, array, Appender;
import std.conv : to;
import std.exception : collectException;
import std.format : formattedWrite, format;
import std.meta : AliasSeq;
import std.range : ElementType, only;
import std.traits : EnumMembers;
import std.typecons : tuple, Tuple, scoped;

import my.container.vector : vector, Vector;
import my.gc.refc : RefCounted;
import my.optional;
import my.set;
import sumtype;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast : Interval, Location;
import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.internal;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.database.type : SchemataFragment;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset,
    Mutation, SourceLocRange, CodeMutant, SchemataChecksum, Checksum;

import dextool.plugin.mutate.backend.analyze.ast;
import dextool.plugin.mutate.backend.analyze.pass_mutant : CodeMutantsResult;

// constant defined by the schemata that test_mutant uses too
/// The function that a mutant reads to see if it should activate.
immutable schemataMutantIdentifier = "dextool_get_mutid()";
/// The environment variable that is read to set the current active mutant.
immutable schemataMutantEnvKey = "DEXTOOL_MUTID";

/// Translate a mutation AST to a schemata.
SchemataResult toSchemata(RefCounted!Ast ast, FilesysIO fio, CodeMutantsResult cresult) @safe {
    auto rval = new SchemataResult;
    auto index = new CodeMutantIndex(cresult);

    final switch (ast.lang) {
    case Language.c:
        goto case;
    case Language.assumeCpp:
        goto case;
    case Language.cpp:
        auto visitor = new CppSchemataVisitor(ast, index, fio, rval);
        scope (exit)
            visitor.dispose;
        ast.accept(visitor);
        break;
    }

    return rval;
}

@safe:

/// Converts a checksum to a 32-bit ID that can be used to activate a mutant.
uint checksumToId(Checksum cs) @safe pure nothrow @nogc {
    return checksumToId(cs.c0);
}

uint checksumToId(ulong cs) @safe pure nothrow @nogc {
    return cast(uint) cs;
}

/// Language generic schemata result.
class SchemataResult {
    static struct Fragment {
        Offset offset;
        const(ubyte)[] text;
        CodeMutant[] mutants;
    }

    static struct Schemata {
        // TODO: change to using appender
        Fragment[] fragments;
    }

    private {
        Schemata[AbsolutePath] schematas;
    }

    Schemata[AbsolutePath] getSchematas() @safe {
        return schematas;
    }

    /// Assuming that all fragments for a file should be merged to one huge.
    private void putFragment(AbsolutePath file, Fragment sf) {
        if (auto v = file in schematas) {
            (*v).fragments ~= sf;
        } else {
            schematas[file] = Schemata([sf]);
        }
    }

    override string toString() @safe {
        import std.range : put;
        import std.utf : byUTF;

        auto w = appender!string();

        void toBuf(Schemata s) {
            foreach (f; s.fragments) {
                formattedWrite(w, "  %s: %s\n", f.offset,
                        (cast(const(char)[]) f.text).byUTF!(const(char)));
                formattedWrite(w, "%(    %s\n%)\n", f.mutants);
            }
        }

        foreach (k; schematas.byKey.array.sort) {
            try {
                formattedWrite(w, "%s:\n", k);
                toBuf(schematas[k]);
            } catch (Exception e) {
            }
        }

        return w.data;
    }
}

/** Build scheman from the fragments.
 *
 * TODO: optimize the implementation. A lot of redundant memory allocations
 * etc.
 *
 * Conservative to only allow up to <user defined> mutants per schemata but it
 * reduces the chance that one failing schemata is "fatal", loosing too many
 * muntats.
 */
struct SchemataBuilder {
    import std.algorithm : any, all;
    import my.container.vector;

    alias Fragment = Tuple!(SchemataFragment, "fragment", CodeMutant[], "mutants");

    alias ET = Tuple!(SchemataFragment[], "fragments", CodeMutant[], "mutants",
            SchemataChecksum, "checksum");

    ///
    bool discardMinScheman;

    /// Max mutants per schema.
    long mutantsPerSchema;

    /// Minimal mutants that a schema must contain for it to be valid.
    long minMutantsPerSchema = 3;

    /// All mutants that have been used in any generated schema.
    Set!CodeMutant isUsed;

    // schemas that in pass1 is less than the threshold
    Vector!Fragment current;
    Vector!Fragment rest;

    /// Save fragments to use them to build schematan.
    void put(scope FilesysIO fio, SchemataResult.Schemata[AbsolutePath] raw) {
        foreach (schema; raw.byKeyValue) {
            const file = fio.toRelativeRoot(schema.key);
            put(schema.value.fragments, file);
        }
    }

    /** Merge analyze fragments into larger schemata fragments. If a schemata
     * fragment is large enough it is converted to a schemata. Otherwise kept
     * for pass2.
     *
     * Schematan from this pass only contain one kind and only affect one file.
     */
    private void put(SchemataResult.Fragment[] fragments, const Path file) {
        foreach (a; fragments) {
            current.put(Fragment(SchemataFragment(file, a.offset, a.text), a.mutants));
        }
    }

    /** Merge schemata fragments to schemas. A schemata from this pass may may
     * contain multiple mutation kinds and span over multiple files.
     */
    Optional!ET next() {
        Index!Path index;
        auto app = appender!(Fragment[])();
        Set!CodeMutant local;

        while (!current.empty) {
            if (local.length >= mutantsPerSchema) {
                // done now so woop
                break;
            }

            auto a = current.front;
            current.popFront;

            if (a.mutants.empty)
                continue;

            if (all!(a => a in isUsed)(a.mutants)) {
                // all mutants in the fragment have already been used in
                // schemas, discard.
                rest.put(a);
                continue;
            }

            if (index.intersect(a.fragment.file, a.fragment.offset)) {
                rest.put(a);
                continue;
            }

            // if any of the mutants in the schema has already been included.
            if (any!(a => a in local)(a.mutants)) {
                rest.put(a);
                continue;
            }

            app.put(a);
            local.add(a.mutants);
            index.put(a.fragment.file, a.fragment.offset);
        }

        if (local.length < minMutantsPerSchema) {
            if (!discardMinScheman) {
                rest.put(app.data);
            }
            return none!ET;
        }

        ET v;
        v.fragments = app.data.map!(a => a.fragment).array;
        v.mutants = local.toArray;
        v.checksum = toSchemataChecksum(v.mutants);
        isUsed.add(v.mutants);
        return some(v);
    }

    bool isDone() @safe pure nothrow const @nogc {
        return current.empty;
    }

    void restart() @safe pure nothrow @nogc {
        current = rest;
        rest.clear;
        isUsed = typeof(isUsed).init;
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
                    (*v) ~= mp.mutants;
                } else {
                    e[mp.offset] = mp.mutants;
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

struct FragmentBuilder {
    BlockChain schema;
    Appender!(CodeMutant[]) mutants;
    Interval interval;
    const(ubyte)[] content;
}

struct MutantHelper {
    this(ref FragmentBuilder fragment, Interval offs) {
        pre = () {
            if (offs.begin <= fragment.interval.begin)
                return null;
            const d = offs.begin - fragment.interval.begin;
            if (d > fragment.content.length)
                return fragment.content;
            return fragment.content[0 .. d];
        }();

        post = () {
            if (offs.end <= fragment.interval.begin)
                return null;
            const d = offs.end - fragment.interval.begin;
            if (d > fragment.content.length)
                return fragment.content;
            return fragment.content[d .. $];
        }();
    }

    const(ubyte)[] pre;
    const(ubyte)[] post;
}

class CppSchemataVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

    RefCounted!Ast ast;
    CodeMutantIndex index;
    SchemataResult result;
    FilesysIO fio;

    private {
        bool saveFragment;
        FragmentBuilder fragment;

        Stack!(Node) nstack;
        uint depth;
    }

    alias visit = DepthFirstVisitor.visit;

    this(RefCounted!Ast ast, CodeMutantIndex index, FilesysIO fio, SchemataResult result) {
        assert(!ast.empty);

        this.ast = ast;
        this.index = index;
        this.fio = fio;
        this.result = result;
    }

    void dispose() {
        ast.release;
    }

    /// Returns: if the previous nodes is of kind `k`.
    bool isDirectParent(Args...)(auto ref Args kinds) {
        if (nstack.empty)
            return false;
        return nstack.back.kind.among(kinds) != 0;
    }

    override void visitPush(Node n) {
        nstack.put(n, ++depth);
    }

    override void visitPop(Node n) {
        nstack.pop;
        --depth;
    }

    override void visit(Function n) @trusted {
        if (saveFragment) {
            accept(n, this);
            return;
        }

        auto firstBlock = () {
            foreach (c; n.children.filter!(a => a.kind == Kind.Block))
                return c;
            return null;
        }();

        if (firstBlock is null) {
            accept(n, this);
            return;
        }

        auto loc = ast.location(firstBlock);

        if (!loc.interval.isZero) {
            saveFragment = true;
            auto fin = fio.makeInput(loc.file);

            fragment = FragmentBuilder.init;
            fragment.interval = loc.interval;
            fragment.content = () {
                // must be at least length 1 because ChainT look at the last
                // value
                if (loc.interval.begin >= loc.interval.end)
                    return " ".rewrite;
                return fin.content[loc.interval.begin .. loc.interval.end];
            }();
            fragment.schema = BlockChain(fragment.content);
        }

        accept(n, this);

        if (saveFragment) {
            result.putFragment(loc.file, rewrite(loc, fragment.schema.generate,
                    fragment.mutants.data));

            fragment = FragmentBuilder.init;
            saveFragment = false;
        }
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
        if (!saveFragment || n.schemaBlacklist)
            return;

        // The schematas from the code below are only needed for e.g. function
        // calls such as if (fn())...

        auto loc = ast.location(n);
        auto mutants = index.get(loc.file, loc.interval);

        if (loc.interval.isZero || mutants.empty)
            return;

        auto fin = fio.makeInput(loc.file);
        auto content = fin.content[loc.interval.begin .. loc.interval.end];
        if (content.empty)
            return;

        auto helper = MutantHelper(fragment, loc.interval);

        foreach (const mutant; mutants) {
            fragment.schema.put(mutant.id.c0, helper.pre,
                    makeMutation(mutant.mut.kind, ast.lang).mutate(
                        fin.content[loc.interval.begin .. loc.interval.end]), helper.post);
        }

        fragment.mutants.put(mutants);
    }

    private void visitBlock(T)(T n, bool requireSyntaxBlock = false) {
        if (!saveFragment || n.schemaBlacklist)
            return;

        auto loc = ast.location(n);
        auto offs = loc.interval;
        auto mutants = index.get(loc.file, offs);

        if (loc.interval.isZero || mutants.empty)
            return;

        auto fin = fio.makeInput(loc.file);

        auto helper = MutantHelper(fragment, loc.interval);

        auto content = () {
            // this is just defensive code. not proven to be a problem.
            if (any!(a => a >= fin.content.length)(only(offs.begin, offs.end)))
                return " ".rewrite;
            return fin.content[offs.begin .. offs.end];
        }();

        foreach (const mutant; mutants) {
            auto mut = () {
                auto mut = makeMutation(mutant.mut.kind, ast.lang).mutate(content);
                if (mut.empty && requireSyntaxBlock)
                    return "{}".rewrite;
                return mut;
            }();
            fragment.schema.put(mutant.id.c0, helper.pre, mut, helper.post);
        }

        fragment.mutants.put(mutants);
    }

    private void visitUnaryOp(T)(T n) {
        if (!saveFragment || n.schemaBlacklist || n.operator.schemaBlacklist)
            return;

        auto loc = ast.location(n);
        auto mutants = index.get(loc.file, loc.interval);

        if (loc.interval.isZero || mutants.empty)
            return;

        auto fin = fio.makeInput(loc.file);
        auto helper = MutantHelper(fragment, loc.interval);

        foreach (const mutant; mutants) {
            fragment.schema.put(mutant.id.c0, helper.pre,
                    makeMutation(mutant.mut.kind, ast.lang).mutate(
                        fin.content[loc.interval.begin .. loc.interval.end]), helper.post);
        }

        fragment.mutants.put(mutants);
    }

    private void visitBinaryOp(T)(T n) @trusted {
        try {
            if (saveFragment) {
                scope v = new BinaryOpVisitor(ast, &index, fio, &fragment);
                v.startVisit(n);
                fragment.mutants.put(v.mutants.toArray);
            }
        } catch (Exception e) {
        }
        accept(n, this);
    }
}

class BinaryOpVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

    RefCounted!Ast ast;
    CodeMutantIndex* index;
    FragmentBuilder* fragment;
    FilesysIO fio;

    // the root of the expression that is being mutated
    Location rootLoc;
    Interval root;

    /// Content of the file that contains the mutant.
    const(ubyte)[] content;

    /// The resulting fragments of the expression.
    Set!CodeMutant mutants;

    this(RefCounted!Ast ast, CodeMutantIndex* index, FilesysIO fio, FragmentBuilder* fragment) {
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

    alias visit = DepthFirstVisitor.visit;

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

        if (locExpr.interval.isZero || locOp.interval.isZero) {
            return;
        }

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

        auto helper = MutantHelper(*fragment, locExpr.interval);

        foreach (const mutant; opMutants) {
            // dfmt off
            fragment.schema.
                put(mutant.id.c0,
                    helper.pre,
                    left,
                    content[locExpr.interval.begin .. locOp.interval.begin],
                    makeMutation(mutant.mut.kind, ast.lang).mutate(content[locOp.interval.begin .. locOp.interval.end]),
                    content[locOp.interval.end .. locExpr.interval.end],
                    right,
                    helper.post
                    );
            // dfmt on
        }

        foreach (const mutant; lhsMutants) {
            // dfmt off
            fragment.schema.put(mutant.id.c0,
                helper.pre,
                left,
                makeMutation(mutant.mut.kind, ast.lang).mutate(content[offsLhs.begin .. offsLhs.end]),
                content[offsLhs.end .. locExpr.interval.end],
                right,
                helper.post
                );
            // dfmt on
        }

        foreach (const mutant; rhsMutants) {
            // dfmt off
            fragment.schema.put(mutant.id.c0,
                helper.pre,
                left,
                content[locExpr.interval.begin .. offsRhs.begin],
                makeMutation(mutant.mut.kind, ast.lang).mutate(content[offsRhs.begin .. offsRhs.end]),
                right,
                helper.post
                );
            // dfmt on
        }

        foreach (const mutant; exprMutants) {
            // dfmt off
            fragment.schema.put(mutant.id.c0,
                helper.pre,
                left,
                makeMutation(mutant.mut.kind, ast.lang).mutate(content[locExpr.interval.begin .. locExpr.interval.end]),
                right,
                helper.post
                );
            // dfmt on
        }

        mutants.add(opMutants);
        mutants.add(lhsMutants);
        mutants.add(rhsMutants);
        mutants.add(exprMutants);
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
        h.put(a.c1.toBytes);
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
 */
struct BlockChain {
    alias Mutant = Tuple!(ulong, "id", const(ubyte)[], "value");
    Set!ulong mutantIds;
    Appender!(Mutant[]) mutants;
    const(ubyte)[] original;

    this(const(ubyte)[] original) {
        this.original = original;
    }

    bool empty() @safe pure nothrow const @nogc {
        return mutants.data.empty;
    }

    /// Returns: `value`
    const(ubyte)[] put(ulong id, const(ubyte)[] value) {
        if (id !in mutantIds) {
            mutantIds.add(id);
            mutants.put(Mutant(id, value));
        }
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
        auto app = appender!(const(ubyte)[])();
        bool isFirst = true;

        foreach (const mutant; mutants.data) {
            if (isFirst) {
                app.put("if (".rewrite);
            } else {
                app.put(" else if (".rewrite);
            }
            isFirst = false;

            app.put(format!"%s == "(schemataMutantIdentifier).rewrite);
            app.put(mutant.id.checksumToId.to!string.rewrite);
            app.put("u".rewrite);
            app.put(") {".rewrite);

            app.put(mutant.value);
            if (!mutant.value.empty && mutant.value[$ - 1] != cast(ubyte) ';') {
                app.put(";".rewrite);
            }

            app.put("} ".rewrite);
        }

        app.put("else {".rewrite);
        app.put(original);
        if (!original.empty && original[$ - 1] != cast(ubyte) ';') {
            app.put(";".rewrite);
        }
        app.put("}".rewrite);

        return app.data;
    }
}

auto contentOrNull(uint begin, uint end, const(ubyte)[] content) {
    if (begin >= end)
        return null;
    return content[begin .. end];
}
