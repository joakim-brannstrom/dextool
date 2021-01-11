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
SchemataResult toSchemata(RefCounted!Ast ast, FilesysIO fio,
        CodeMutantsResult cresult, long mutantsPerSchema) @safe {
    auto rval = new SchemataResult(fio, mutantsPerSchema);
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

/// Language generic
class SchemataResult {
    import dextool.plugin.mutate.backend.database.type : SchemataFragment;
    import dextool.plugin.mutate.backend.analyze.utility : Index;

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
        FilesysIO fio;
        const long mutantsPerSchema;
    }

    this(FilesysIO fio, long mutantsPerSchema) {
        this.fio = fio;
        this.mutantsPerSchema = mutantsPerSchema;
    }

    SchematasRange getSchematas() @safe {
        return SchematasRange(fio, schematas, mutantsPerSchema);
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

private:

struct SchematasRange {
    alias ET = Tuple!(SchemataFragment[], "fragments", CodeMutant[], "mutants",
            SchemataChecksum, "checksum");

    private {
        ET[] values;
    }

    this(scope FilesysIO fio, SchemataResult.Schemata[AbsolutePath] raw, long mutantsPerSchema) {
        auto values_ = appender!(ET[])();
        auto builder = SchemataBuilder(mutantsPerSchema);

        foreach (schema; raw.byKeyValue) {
            auto file = fio.toRelativeRoot(schema.key);
            builder.pass1(schema.value.fragments, file)
                .match!((Some!ET a) => values_.put(a.value), (None a) {});
        }

        while (!builder.pass2Data.empty) {
            builder.pass2.match!((Some!ET a) => values_.put(a.value), (None a) {});
        }

        this.values = values_.data;
    }

    ET front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return values[0];
    }

    void popFront() @safe {
        assert(!empty, "Can't pop front of an empty range");
        values = values[1 .. $];
    }

    bool empty() @safe pure nothrow const @nogc {
        return values.empty;
    }
}

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

class CppSchemataVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;
    import dextool.plugin.mutate.backend.mutation_type.aor : aorMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.lcr : lcrMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.lcrb : lcrbMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.ror : rorMutationsAll, rorpMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.sdl : stmtDelMutationsRaw;

    RefCounted!Ast ast;
    CodeMutantIndex index;
    SchemataResult result;
    FilesysIO fio;

    private {
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

    override void visitPush(Node n) {
        nstack.put(n, ++depth);
    }

    override void visitPop(Node n) {
        nstack.pop;
        --depth;
    }

    override void visit(Expr n) {
        accept(n, this);
        visitBlock!ExpressionChain(n);
    }

    override void visit(Block n) {
        visitBlock!(BlockChain)(n);
        accept(n, this);
    }

    override void visit(Loop n) @trusted {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(BranchBundle n) @trusted {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(Call n) {
        visitBlock!(BlockChain)(n);
        accept(n, this);
    }

    override void visit(Return n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(BinaryOp n) {
        // these are operators such as x += 2
        visitBlock!(BlockChain)(n);
        accept(n, this);
    }

    override void visit(OpAssign n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpAssignAdd n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpAssignAndBitwise n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpAssignDiv n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpAssignMod n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpAssignMul n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpAssignOrBitwise n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpAssignSub n) {
        visitBlock!BlockChain(n);
        accept(n, this);
    }

    override void visit(OpNegate n) {
        import dextool.plugin.mutate.backend.mutation_type.uoi : uoiLvalueMutationsRaw;

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

    override void visit(Branch n) {
        if (n.inside !is null) {
            visitBlock!BlockChain(n.inside);
        }
        accept(n, this);
    }

    private void visitCondition(T)(T n) @trusted {
        if (n.blacklist || n.schemaBlacklist)
            return;

        // The schematas from the code below are only needed for e.g. function
        // calls such as if (fn())...

        auto loc = ast.location(n);
        auto mutants = index.get(loc.file, loc.interval);

        if (loc.interval.isZero)
            return;

        if (mutants.empty)
            return;

        auto fin = fio.makeInput(loc.file);
        auto schema = ExpressionChain(fin.content[loc.interval.begin .. loc.interval.end]);
        foreach (const mutant; mutants) {
            // dfmt off
            schema.put(mutant.id.c0,
                makeMutation(mutant.mut.kind, ast.lang).mutate(fin.content[loc.interval.begin .. loc.interval.end]),
                );
            // dfmt on
        }

        result.putFragment(loc.file, rewrite(loc, schema.generate, mutants));
    }

    private void visitBlock(ChainT, T)(T n) {
        if (n.blacklist || n.schemaBlacklist)
            return;

        auto loc = ast.location(n);
        if (loc.interval.isZero)
            return;

        auto offs = loc.interval;
        auto mutants = index.get(loc.file, offs);

        if (mutants.empty)
            return;

        auto fin = fio.makeInput(loc.file);

        auto content = () {
            // TODO: why does it crash when null is returned? it should work...
            // switch statements with fallthrough case-branches have an
            // offs.begin == offs.end
            if (offs.begin >= offs.end) {
                return " ".rewrite;
            }
            // this is just defensive code. not proven to be a problem.
            if (any!(a => a >= fin.content.length)(only(offs.begin, offs.end))) {
                return " ".rewrite;
            }
            return fin.content[offs.begin .. offs.end];
        }();

        auto schema = ChainT(content);
        foreach (const mutant; mutants) {
            schema.put(mutant.id.c0, makeMutation(mutant.mut.kind, ast.lang).mutate(content));
        }

        result.putFragment(loc.file, rewrite(loc, schema.generate, mutants));
    }

    private void visitUnaryOp(T)(T n) {
        if (n.blacklist || n.schemaBlacklist)
            return;

        auto loc = ast.location(n.operator);
        auto locExpr = ast.location(n);
        if (loc.interval.isZero || locExpr.interval.isZero)
            return;

        auto mutants = index.get(loc.file, loc.interval);

        if (mutants.empty)
            return;

        auto fin = fio.makeInput(loc.file);
        auto schema = ExpressionChain(fin.content[locExpr.interval.begin .. locExpr.interval.end]);
        foreach (const mutant; mutants) {
            schema.put(mutant.id.c0, makeMutation(mutant.mut.kind, ast.lang)
                    .mutate(fin.content[loc.interval.begin .. loc.interval.end]),
                    fin.content[loc.interval.end .. locExpr.interval.end]);
        }

        result.putFragment(loc.file, rewrite(locExpr, schema.generate, mutants));
    }

    private void visitBinaryOp(T)(T n) @trusted {
        try {
            auto v = scoped!BinaryOpVisitor(ast, &index, fio, n);
            v.startVisit(n);
            result.putFragment(v.rootLoc.file, rewrite(v.rootLoc,
                    v.schema.generate, v.mutants.toArray));
        } catch (Exception e) {
        }
    }
}

class BinaryOpVisitor : DepthFirstVisitor {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;
    import dextool.plugin.mutate.backend.mutation_type.aor : aorMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.lcr : lcrMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.lcrb : lcrbMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.ror : rorMutationsAll, rorpMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.sdl : stmtDelMutationsRaw;

    RefCounted!Ast ast;
    CodeMutantIndex* index;
    FilesysIO fio;

    // the root of the expression that is being mutated
    Location rootLoc;
    Interval root;

    /// Content of the file that contains the mutant.
    const(ubyte)[] content;

    /// The resulting fragments of the expression.
    ExpressionChain schema;
    Set!CodeMutant mutants;

    this(T)(RefCounted!Ast ast, CodeMutantIndex* index, FilesysIO fio, T root) {
        this.ast = ast;
        this.index = index;
        this.fio = fio;
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

        schema = ExpressionChain(content[root.begin .. root.end]);

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
        if (n.blacklist || n.schemaBlacklist)
            return;

        auto locExpr = ast.location(n);
        auto locOp = ast.location(n.operator);

        if (locExpr.interval.isZero || locOp.interval.isZero) {
            return;
        }

        auto left = contentOrNull(root.begin, locExpr.interval.begin, content);

        // must check otherwise it crash on intervals that have zero length e.g. [9, 9].
        auto right = contentOrNull(locExpr.interval.end, root.end, content);

        auto opMutants = index.get(locOp.file, locOp.interval);

        auto exprMutants = index.get(locOp.file, locExpr.interval);

        auto offsLhs = Offset(locExpr.interval.begin, locOp.interval.end);
        auto lhsMutants = index.get(locOp.file, offsLhs);

        auto offsRhs = Offset(locOp.interval.begin, locExpr.interval.end);
        auto rhsMutants = index.get(locOp.file, offsRhs);

        if (opMutants.empty && lhsMutants.empty && rhsMutants.empty && exprMutants.empty)
            return;

        foreach (const mutant; opMutants) {
            // dfmt off
            schema.
                put(mutant.id.c0,
                    left,
                    content[locExpr.interval.begin .. locOp.interval.begin],
                    makeMutation(mutant.mut.kind, ast.lang).mutate(content[locOp.interval.begin .. locOp.interval.end]),
                    content[locOp.interval.end .. locExpr.interval.end],
                    right);
            // dfmt on
        }

        foreach (const mutant; lhsMutants) {
            // dfmt off
            schema.put(mutant.id.c0,
                left,
                makeMutation(mutant.mut.kind, ast.lang).mutate(content[offsLhs.begin .. offsLhs.end]),
                content[offsLhs.end .. locExpr.interval.end],
                right);
            // dfmt on
        }

        foreach (const mutant; rhsMutants) {
            // dfmt off
            schema.put(mutant.id.c0,
                left,
                content[locExpr.interval.begin .. offsRhs.begin],
                makeMutation(mutant.mut.kind, ast.lang).mutate(content[offsRhs.begin .. offsRhs.end]),
                right);
            // dfmt on
        }

        foreach (const mutant; exprMutants) {
            // dfmt off
            schema.put(mutant.id.c0,
                left,
                makeMutation(mutant.mut.kind, ast.lang).mutate(content[locExpr.interval.begin .. locExpr.interval.end]),
                right);
            // dfmt on
        }

        mutants.add(opMutants ~ lhsMutants ~ rhsMutants ~ exprMutants);
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

/** Accumulate multiple modifications for an expression to then generate a via
 * ternery operator that activate one mutant if necessary.
 *
 * A id can only be added once to the chain. This ensure that there are no
 * duplications. This can happen when e.g. adding rorFalse and dcrFalse to an
 * expression group. They both result in the same source code mutation thus
 * only one of them is actually needed. This deduplications this case.
 */
struct ExpressionChain {
    alias Mutant = Tuple!(ulong, "id", const(ubyte)[], "value");
    Appender!(Mutant[]) mutants;
    Set!ulong mutantIds;
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
        app.put("(".rewrite);
        foreach (const mutant; mutants.data) {
            app.put(format!"(%s == "(schemataMutantIdentifier).rewrite);
            app.put(mutant.id.checksumToId.to!string.rewrite);
            app.put("u".rewrite);
            app.put(") ? (".rewrite);
            app.put(mutant.value);
            app.put(") : ".rewrite);
        }
        app.put("(".rewrite);
        app.put(original);
        app.put("))".rewrite);
        return app.data;
    }
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
            app.put(";} ".rewrite);
        }

        app.put("else {".rewrite);
        app.put(original);
        if (original[$ - 1 .. $] != ";".rewrite) {
            app.put(";".rewrite);
        }
        app.put(";}".rewrite);

        return app.data;
    }
}

auto contentOrNull(uint begin, uint end, const(ubyte)[] content) {
    if (begin >= end)
        return null;
    return content[begin .. end];
}

/** Build schematan from the individual fragments for a individual file.
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

    alias ET = SchematasRange.ET;
    const long mutantsPerSchema;
    // hardcoded for now the minimum req. for a schema to be saved.
    immutable long minMutantsPerSchema = 2;

    /// All mutants that have been included in any generated schema.
    Set!CodeMutant global;

    // schemas that in pass1 is less than the threshold
    Vector!Fragment pass2Data;

    /** Merge analyze fragments into larger schemata fragments. If a schemata
     * fragment is large enough it is converted to a schemata. Otherwise kept
     * for pass2.
     *
     * Schematan from this pass only contain one kind and only affect one file.
     */
    Optional!ET pass1(SchemataResult.Fragment[] fragments, Path file) {
        // overlapping mutants is not supported "yet" thus make sure no
        // fragment overlap with another fragment.
        Index!byte index;

        auto app = appender!(Fragment[])();

        Set!CodeMutant local;
        foreach (a; fragments) {
            if (local.length >= mutantsPerSchema || index.intersect(0, a.offset)) {
                pass2Data.put(Fragment(SchemataFragment(file, a.offset, a.text), a.mutants));
                continue;
            }

            // all mutants in the fragment have already been generated, discard.
            if (all!(a => a in global)(a.mutants)) {
                continue;
            }

            // if any of the mutants in the schema has already been included.
            if (any!(a => a in local)(a.mutants)) {
                pass2Data.put(Fragment(SchemataFragment(file, a.offset, a.text), a.mutants));
                continue;
            }

            app.put(Fragment(SchemataFragment(file, a.offset, a.text), a.mutants));
            local.add(a.mutants);
            index.put(0, a.offset);
        }

        if (local.length >= mutantsPerSchema) {
            ET v;
            v.fragments = app.data.map!(a => a.fragment).array;
            v.mutants = local.toArray;
            v.checksum = toSchemataChecksum(v.mutants);
            global.add(v.mutants);
            return some(v);
        } else if (!local.empty) {
            pass2Data.put(app.data);
        }

        return none!ET;
    }

    /** Merge schemata fragments to schemas. A schemata from this pass may may
     * contain multiple mutation kinds and span over multiple files.
     */
    Optional!ET pass2() {
        Index!Path index;

        auto app = appender!(SchemataFragment[])();
        Set!CodeMutant local;

        typeof(pass2Data) rest;
        scope (exit)
            pass2Data = rest;

        foreach (a; pass2Data) {
            if (local.length >= mutantsPerSchema
                    || index.intersect(a.fragment.file, a.fragment.offset)) {
                rest.put(a);
                continue;
            }

            // all mutants in the fragment have already been generated, discard.
            if (all!(a => a in global)(a.mutants)) {
                continue;
            }

            // if any of the mutants in the schema has already been included.
            if (any!(a => a in local)(a.mutants)) {
                rest.put(a);
                continue;
            }

            app.put(a.fragment);
            local.add(a.mutants);
            index.put(a.fragment.file, a.fragment.offset);
        }

        if (local.length <= minMutantsPerSchema)
            return none!ET;

        ET v;
        v.fragments = app.data;
        v.mutants = local.toArray;
        v.checksum = toSchemataChecksum(v.mutants);
        global.add(v.mutants);
        return some(v);
    }
}
