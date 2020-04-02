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
import std.algorithm : among, map, sort, filter, canFind, copy, uniq;
import std.array : appender, empty, array, Appender;
import std.conv : to;
import std.exception : collectException;
import std.format : formattedWrite;
import std.meta : AliasSeq;
import std.range : retro, ElementType;
import std.traits : EnumMembers;
import std.typecons : Nullable, tuple, Tuple, scoped;

import automem : vector, Vector;

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

/// Translate a mutation AST to a schemata.
SchemataResult toSchemata(ref Ast ast, FilesysIO fio, CodeMutantsResult cresult) @trusted {
    auto rval = new SchemataResult(fio);
    auto index = scoped!CodeMutantIndex(cresult);

    final switch (ast.lang) {
    case Language.c:
        break;
    case Language.assumeCpp:
        goto case;
    case Language.cpp:
        auto visitor = () @trusted {
            return new CppSchemataVisitor(&ast, index, fio, rval);
        }();
        ast.accept(visitor);
        break;
    }

    return rval;
}

@safe:

/// Language generic
class SchemataResult {
    import dextool.set;
    import dextool.plugin.mutate.backend.database.type : SchemataFragment;

    static struct Fragment {
        Offset offset;
        const(ubyte)[] text;
    }

    static struct Schemata {
        Fragment[] fragments;
        Set!CodeMutant mutants;
    }

    private {
        Schemata[MutantGroup][AbsolutePath] schematas;
        FilesysIO fio;
    }

    this(FilesysIO fio) {
        this.fio = fio;
    }

    SchematasRange getSchematas() @safe {
        return SchematasRange(fio, schematas);
    }

    /// Assuming that all fragments for a file should be merged to one huge.
    private void putFragment(AbsolutePath file, MutantGroup g, Fragment sf, CodeMutant[] m) {
        if (auto v = file in schematas) {
            (*v)[g].fragments ~= sf;
            (*v)[g].mutants.add(m);
        } else {
            foreach (a; [EnumMembers!MutantGroup]) {
                schematas[file][a] = Schemata.init;
            }
            schematas[file][g] = Schemata([sf], m.toSet);
        }
    }

    override string toString() @safe {
        import std.range : put;
        import std.utf : byUTF;

        auto w = appender!string();

        void toBuf(Schemata s) {
            formattedWrite(w, "Mutants\n%(%s\n%)\n", s.mutants.toArray);
            foreach (f; s.fragments) {
                formattedWrite(w, "%s: %s\n", f.offset,
                        (cast(const(char)[]) f.text).byUTF!(const(char)));
            }
        }

        void toBufGroups(Schemata[MutantGroup] s) {
            foreach (a; s.byKeyValue) {
                formattedWrite(w, "Group %s ", a.key);
                toBuf(a.value);
            }
        }

        foreach (k; schematas.byKey.array.sort) {
            try {
                formattedWrite(w, "%s:\n", k);
                toBufGroups(schematas[k]);
            } catch (Exception e) {
            }
        }

        return w.data;
    }
}

private:

/** All mutants for a file that is part of the same group are merged to one schemata.
 *
 * Each file can have multiple groups.
 */
enum MutantGroup {
    none,
    aor,
    ror,
    lcr,
    lcrb,
    // the operator mutants that replace the whole expression. The schema have
    // a high probability of working because it isn't dependent on the
    // operators being implemented for lhs/rhs
    opExpr,
    dcc,
    dcr,
}

auto defaultHeader(Path f) {
    static immutable code = `
#ifndef DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#define DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t gDEXTOOL_MUTID;

__attribute__((constructor))
static void init_dextool_mutid(void) {
    gDEXTOOL_MUTID = 0;
    const char* e = getenv("DEXTOOL_MUTID");
    if (e != NULL) {
        sscanf(e, "%lu", &gDEXTOOL_MUTID);
    }
}

#endif /* DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD */
`;
    return SchemataFragment(f, Offset(0, 0), cast(const(ubyte)[]) code);
}

struct SchematasRange {
    alias ET = Tuple!(SchemataFragment[], "fragments", CodeMutant[], "mutants",
            SchemataChecksum, "checksum");

    private {
        FilesysIO fio;
        ET[] values;
    }

    this(FilesysIO fio, SchemataResult.Schemata[MutantGroup][AbsolutePath] raw) {
        this.fio = fio;

        // TODO: maybe accumulate the fragments for more files? that would make
        // it possible to easily create a large schemata.
        auto values_ = appender!(ET[])();
        foreach (group; raw.byKeyValue) {
            auto relp = fio.toRelativeRoot(group.key);
            foreach (a; group.value.byKeyValue) {
                auto app = appender!(SchemataFragment[])();
                ET v;

                app.put(defaultHeader(relp));
                a.value.fragments.map!(a => SchemataFragment(relp, a.offset, a.text)).copy(app);
                v.fragments = app.data;

                v.mutants = a.value.mutants.toArray;
                v.checksum = toSchemataChecksum(v.mutants);
                values_.put(v);
            }
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
    import dextool.plugin.mutate.backend.mutation_type.aor : aorMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.dcc : dccMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.dcr : dcrMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.lcr : lcrMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.lcrb : lcrbMutationsAll;
    import dextool.plugin.mutate.backend.mutation_type.ror : rorMutationsAll, rorpMutationsAll;

    Ast* ast;
    CodeMutantIndex index;
    SchemataResult result;
    FilesysIO fio;

    this(Ast* ast, CodeMutantIndex index, FilesysIO fio, SchemataResult result) {
        this.ast = ast;
        this.index = index;
        this.fio = fio;
        this.result = result;
    }

    alias visit = DepthFirstVisitor.visit;

    override void visit(OpAndBitwise n) {
        visitBinaryOp(n, MutantGroup.lcrb, lcrbMutationsAll);
        accept(n, this);
    }

    override void visit(OpAnd n) {
        visitBinaryOp(n, MutantGroup.lcr, lcrMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpOrBitwise n) {
        visitBinaryOp(n, MutantGroup.lcrb, lcrbMutationsAll);
        accept(n, this);
    }

    override void visit(OpOr n) {
        visitBinaryOp(n, MutantGroup.lcr, lcrMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpLess n) {
        visitBinaryOp(n, MutantGroup.ror, rorMutationsAll ~ rorpMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpLessEq n) {
        visitBinaryOp(n, MutantGroup.ror, rorMutationsAll ~ rorpMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpGreater n) {
        visitBinaryOp(n, MutantGroup.ror, rorMutationsAll ~ rorpMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpGreaterEq n) {
        visitBinaryOp(n, MutantGroup.ror, rorMutationsAll ~ rorpMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpEqual n) {
        visitBinaryOp(n, MutantGroup.ror, rorMutationsAll ~ rorpMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpNotEqual n) {
        visitBinaryOp(n, MutantGroup.ror, rorMutationsAll ~ rorpMutationsAll);
        visitBinaryOp(n, MutantGroup.dcc, dccMutationsAll);
        visitBinaryOp(n, MutantGroup.dcr, dcrMutationsAll);
        accept(n, this);
    }

    override void visit(OpAdd n) {
        visitBinaryOp(n, MutantGroup.aor, aorMutationsAll);
        accept(n, this);
    }

    override void visit(OpSub n) {
        visitBinaryOp(n, MutantGroup.aor, aorMutationsAll);
        accept(n, this);
    }

    override void visit(OpMul n) {
        visitBinaryOp(n, MutantGroup.aor, aorMutationsAll);
        accept(n, this);
    }

    override void visit(OpMod n) {
        visitBinaryOp(n, MutantGroup.aor, aorMutationsAll);
        accept(n, this);
    }

    override void visit(OpDiv n) {
        visitBinaryOp(n, MutantGroup.aor, aorMutationsAll);
        accept(n, this);
    }

    private void visitBinaryOp(T)(T n, const MutantGroup group, const Mutation.Kind[] opKinds_) {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

        //TODO: reduce the copy/paste code

        auto loc = ast.location(n.operator);
        auto locExpr = ast.location(n);
        auto locLhs = ast.location(n.lhs);
        auto locRhs = ast.location(n.rhs);
        if (locLhs is null || locRhs is null) {
            return;
        }

        auto opKinds = opKinds_.dup.sort.uniq.array;

        auto opMutants = index.get(loc.file, loc.interval)
            .filter!(a => canFind(opKinds, a.mut.kind)).array;

        auto exprMutants = index.get(loc.file, locExpr.interval)
            .filter!(a => canFind(opKinds, a.mut.kind)).array;

        auto offsLhs = Offset(locLhs.interval.begin, loc.interval.end);
        auto lhsMutants = index.get(loc.file, offsLhs)
            .filter!(a => canFind(opKinds, a.mut.kind)).array;

        auto offsRhs = Offset(loc.interval.begin, locRhs.interval.end);
        auto rhsMutants = index.get(loc.file, offsRhs)
            .filter!(a => canFind(opKinds, a.mut.kind)).array;

        if (opMutants.empty && lhsMutants.empty && rhsMutants.empty)
            return;

        auto fin = fio.makeInput(loc.file);
        auto schema = ExpressionChain(fin.content[locExpr.interval.begin .. locExpr.interval.end]);
        auto robustSchema = ExpressionChain(
                fin.content[locExpr.interval.begin .. locExpr.interval.end]);

        foreach (const mutant; opMutants) {
            schema.put(mutant.id.c0, fin.content[locLhs.interval.begin .. locLhs.interval.end],
                    makeMutation(mutant.mut.kind, ast.lang).mutate(fin.content[loc.interval.begin .. loc.interval.end]),
                    fin.content[locRhs.interval.begin .. locRhs.interval.end]);
        }

        foreach (const mutant; lhsMutants) {
            robustSchema.put(mutant.id.c0, schema.put(mutant.id.c0,
                    makeMutation(mutant.mut.kind, ast.lang).mutate(fin.content[offsLhs.begin .. offsLhs.end]),
                    fin.content[locRhs.interval.begin .. locRhs.interval.end]));
        }

        foreach (const mutant; rhsMutants) {
            robustSchema.put(mutant.id.c0, schema.put(mutant.id.c0,
                    fin.content[locLhs.interval.begin .. locLhs.interval.end],
                    makeMutation(mutant.mut.kind, ast.lang).mutate(
                    fin.content[offsRhs.begin .. offsRhs.end])));
        }

        foreach (const mutant; exprMutants) {
            robustSchema.put(mutant.id.c0, schema.put(mutant.id.c0,
                    makeMutation(mutant.mut.kind, ast.lang).mutate(
                    fin.content[locExpr.interval.begin .. locExpr.interval.end])));
        }

        result.putFragment(loc.file, group, rewrite(locExpr, schema.generate),
                opMutants ~ lhsMutants ~ rhsMutants ~ exprMutants);
        result.putFragment(loc.file, MutantGroup.opExpr, rewrite(locExpr,
                robustSchema.generate), lhsMutants ~ rhsMutants ~ exprMutants);
    }
}

const(ubyte)[] rewrite(string s) {
    return cast(const(ubyte)[]) s;
}

SchemataResult.Fragment rewrite(Location loc, string s) {
    return rewrite(loc, cast(const(ubyte)[]) s);
}

/// Create a fragment that rewrite a source code location to `s`.
SchemataResult.Fragment rewrite(Location loc, const(ubyte)[] s) {
    return SchemataResult.Fragment(loc.interval, s);
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
 */
struct ExpressionChain {
    alias Mutant = Tuple!(ulong, "id", const(ubyte)[], "value");
    Appender!(Mutant[]) mutants;
    const(ubyte)[] original;

    this(const(ubyte)[] original) {
        this.original = original;
    }

    /// Returns: `value`
    const(ubyte)[] put(ulong id, const(ubyte)[] value) {
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
        auto app = appender!(const(ubyte)[])();
        app.put("(".rewrite);
        foreach (const mutant; mutants.data) {
            app.put("(gDEXTOOL_MUTID == ".rewrite);
            app.put(mutant.id.to!string.rewrite);
            app.put("ull".rewrite);
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
