/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains functionality to take an unprocessed mutation point and
generate a mutant for it.
*/
module dextool.plugin.mutate.backend.generate_mutant;

import std.exception : collectException;
import std.typecons : Nullable;
import logger = std.experimental.logger;
import std.path : buildPath;

import dextool.type : AbsolutePath, ExitStatusType, FileName, DirName;
import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    MutationId, spinSqlQuery;
import dextool.plugin.mutate.backend.type : Language;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeOutput,
    ValidateLoc;
import dextool.plugin.mutate.type : MutationKind;

enum GenerateMutantStatus {
    error,
    filesysError,
    databaseError,
    checksumError,
    noMutation,
    ok
}

ExitStatusType runGenerateMutant(ref Database db, MutationKind[] kind,
        Nullable!long user_mutation, FilesysIO fio, ValidateLoc val_loc) @safe nothrow {
    import dextool.plugin.mutate.backend.utility : toInternal;

    Nullable!MutationEntry mutp;
    if (!user_mutation.isNull) {
        mutp = spinSqlQuery!(() {
            return db.getMutation(MutationId(user_mutation.get));
        });
        logger.error(mutp.isNull, "No such mutation id: ", user_mutation.get).collectException;
    } else {
        auto next_m = spinSqlQuery!(() { return db.nextMutation(kind.toInternal); });
        mutp = next_m.entry;
    }
    if (mutp.isNull)
        return ExitStatusType.Errors;

    AbsolutePath mut_file;
    try {
        mut_file = AbsolutePath(FileName(mutp.file), DirName(fio.getOutputDir));
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    ubyte[] content;
    try {
        content = fio.makeInput(mut_file).read;
        if (content.length == 0)
            return ExitStatusType.Errors;
    } catch (Exception e) {
        collectException(logger.error(e.msg));
        return ExitStatusType.Errors;
    }

    ExitStatusType exit_st;
    try {
        auto ofile = makeOutputFilename(val_loc, fio, mut_file);
        auto fout = fio.makeOutput(ofile);
        auto res = generateMutant(db, mutp, content, fout);
        if (res.status == GenerateMutantStatus.ok) {
            logger.infof("%s Mutate from '%s' to '%s' in %s", mutp.id, res.from, res.to, ofile);
            exit_st = ExitStatusType.Ok;
        }
    } catch (Exception e) {
        collectException(logger.error(e.msg));
    }

    return exit_st;
}

private AbsolutePath makeOutputFilename(ValidateLoc val_loc, FilesysIO fio, AbsolutePath file) @safe {
    import std.path;
    import dextool.type : FileName;

    if (val_loc.shouldMutate(file))
        return file;

    return AbsolutePath(FileName(buildPath(fio.getOutputDir, file.baseName)));
}

struct GenerateMutantResult {
    GenerateMutantStatus status;
    const(char)[] from;
    const(char)[] to;
}

auto generateMutant(ref Database db, MutationEntry mutp, const(ubyte)[] content, ref SafeOutput fout) @safe nothrow {
    import dextool.plugin.mutate.backend.utility : checksum, Checksum;

    if (mutp.mp.mutations.length == 0)
        return GenerateMutantResult(GenerateMutantStatus.noMutation);

    Nullable!Checksum db_checksum;
    try {
        db_checksum = db.getFileChecksum(mutp.file);
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
        return GenerateMutantResult(GenerateMutantStatus.databaseError);
    }

    Checksum f_checksum;
    try {
        f_checksum = checksum(cast(const(ubyte)[]) content);
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
        return GenerateMutantResult(GenerateMutantStatus.filesysError);
    }

    if (db_checksum.isNull) {
        logger.errorf("Database contains erroneous data. A mutation point for %s exist but the file has no checksum",
                mutp.file).collectException;
        return GenerateMutantResult(GenerateMutantStatus.databaseError);
    } else if (db_checksum != f_checksum) {
        logger.errorf(
                "Unable to mutate %s (%s%s) because the checksum is different from the one in the database (%s%s)",
                mutp.file, f_checksum.c0,
                f_checksum.c1, db_checksum.c0, db_checksum.c1).collectException;
        return GenerateMutantResult(GenerateMutantStatus.checksumError);
    }

    // must copy the memory because content is backed by a memory mapped file and can thus change
    const string from_ = (cast(const(char)[]) content[mutp.mp.offset.begin .. mutp.mp.offset.end])
        .idup;

    auto mut = makeMutation(mutp.mp.mutations[0].kind, mutp.lang);

    try {
        fout.write(mut.top());
        auto s = content.drop(mutp.mp.offset);
        fout.write(s.front);
        s.popFront;

        const string to_ = mut.mutate(from_);
        fout.write(to_);
        fout.write(s.front);

        // #SPC-plugin_mutate_file_security-header_as_warning
        fout.write("\n/* DEXTOOL: THIS FILE IS MUTATED */");

        return GenerateMutantResult(GenerateMutantStatus.ok, from_, to_);
    } catch (Exception e) {
        return GenerateMutantResult(GenerateMutantStatus.filesysError);
    }
}

auto makeMutation(Mutation.Kind kind, Language lang) {
    import std.format : format;

    MutateImpl m;
    m.top = () { return null; };
    m.mutate = (const(char)[] from) { return null; };

    auto clangTrue(const(char)[]) {
        if (lang == Language.c)
            return "1";
        else
            return "true";
    }

    auto clangFalse(const(char)[]) {
        if (lang == Language.c)
            return "0";
        else
            return "false";
    }

    final switch (kind) with (Mutation.Kind) {
        /// the kind is not initialized thus can only ignore the point
    case none:
        break;
        /// Relational operator replacement
    case rorLT:
        goto case;
    case rorpLT:
        m.mutate = (const(char)[] expr) { return ("<"); };
        break;
    case rorLE:
        goto case;
    case rorpLE:
        m.mutate = (const(char)[] expr) { return "<="; };
        break;
    case rorGT:
        goto case;
    case rorpGT:
        m.mutate = (const(char)[] expr) { return ">"; };
        break;
    case rorGE:
        goto case;
    case rorpGE:
        m.mutate = (const(char)[] expr) { return ">="; };
        break;
    case rorEQ:
        goto case;
    case rorpEQ:
        m.mutate = (const(char)[] expr) { return "=="; };
        break;
    case rorNE:
        goto case;
    case rorpNE:
        m.mutate = (const(char)[] expr) { return "!="; };
        break;
    case rorTrue:
        m.mutate = &clangTrue;
        break;
    case rorFalse:
        m.mutate = &clangFalse;
        break;
        /// Logical connector replacement
        /// #SPC-plugin_mutate_mutation_lcr
    case lcrAnd:
        m.mutate = (const(char)[] expr) { return "&&"; };
        break;
    case lcrOr:
        m.mutate = (const(char)[] expr) { return "||"; };
        break;
        /// Arithmetic operator replacement
        /// #SPC-plugin_mutate_mutation_aor
    case aorMul:
        m.mutate = (const(char)[] expr) { return "*"; };
        break;
    case aorDiv:
        m.mutate = (const(char)[] expr) { return "/"; };
        break;
    case aorRem:
        m.mutate = (const(char)[] expr) { return "%"; };
        break;
    case aorAdd:
        m.mutate = (const(char)[] expr) { return "+"; };
        break;
    case aorSub:
        m.mutate = (const(char)[] expr) { return "-"; };
        break;
    case aorMulAssign:
        m.mutate = (const(char)[] expr) { return "*="; };
        break;
    case aorDivAssign:
        m.mutate = (const(char)[] expr) { return "/="; };
        break;
    case aorRemAssign:
        m.mutate = (const(char)[] expr) { return "%="; };
        break;
    case aorAddAssign:
        m.mutate = (const(char)[] expr) { return "+="; };
        break;
    case aorSubAssign:
        m.mutate = (const(char)[] expr) { return "-="; };
        break;
        /// Unary operator insert on an lvalue
        /// #SPC-plugin_mutate_mutation_uoi
    case uoiPostInc:
        m.mutate = (const(char)[] expr) { return format("%s++", expr); };
        break;
    case uoiPostDec:
        m.mutate = (const(char)[] expr) { return format("%s--", expr); };
        break;
        // these work for rvalue
    case uoiPreInc:
        m.mutate = (const(char)[] expr) { return format("++%s", expr); };
        break;
    case uoiPreDec:
        m.mutate = (const(char)[] expr) { return format("--%s", expr); };
        break;
    case uoiAddress:
        m.mutate = (const(char)[] expr) { return format("&%s", expr); };
        break;
    case uoiIndirection:
        m.mutate = (const(char)[] expr) { return format("*%s", expr); };
        break;
    case uoiPositive:
        m.mutate = (const(char)[] expr) { return format("+%s", expr); };
        break;
    case uoiNegative:
        m.mutate = (const(char)[] expr) { return format("-%s", expr); };
        break;
    case uoiComplement:
        m.mutate = (const(char)[] expr) { return format("~%s", expr); };
        break;
    case uoiNegation:
        m.mutate = (const(char)[] expr) { return format("!%s", expr); };
        break;
    case uoiSizeof_:
        m.mutate = (const(char)[] expr) { return format("sizeof(%s)", expr); };
        break;
        /// Absolute value replacement
        /// #SPC-plugin_mutate_mutation_abs
    case absPos:
        m.top = () { return preambleAbs; };
        m.mutate = (const(char)[] b) { return format("abs_dextool(%s)", b); };
        break;
    case absNeg:
        m.top = () { return preambleAbs; };
        m.mutate = (const(char)[] b) { return format("-abs_dextool(%s)", b); };
        break;
    case absZero:
        m.top = () { return preambleAbs; };
        m.mutate = (const(char)[] b) {
            return format("fail_on_zero_dextool(%s)", b);
        };
        break;
    case stmtDel:
        /// #SPC-plugin_mutate_mutations_statement_del
        // delete by commenting out the code block
        m.mutate = (const(char)[] expr) { return format("/*%s*/", expr); };
        break;
        /// Conditional Operator Replacement (reduced set)
        /// #SPC-plugin_mutate_mutation_cor
    case corAnd:
        assert(0);
    case corOr:
        assert(0);
    case corFalse:
        m.mutate = &clangFalse;
        break;
    case corLhs:
        // delete by commenting out
        m.mutate = (const(char)[] expr) { return format("/*%s*/", expr); };
        break;
    case corRhs:
        // delete by commenting out
        m.mutate = (const(char)[] expr) { return format("/*%s*/", expr); };
        break;
    case corEQ:
        m.mutate = (const(char)[] expr) { return "=="; };
        break;
    case corNE:
        m.mutate = (const(char)[] expr) { return "!="; };
        break;
    case corTrue:
        m.mutate = &clangTrue;
        break;
    case dccTrue:
        m.mutate = &clangTrue;
        break;
    case dccFalse:
        m.mutate = &clangFalse;
        break;
    case dccBomb:
        // assigning null should crash the program, thus a 'bomb'
        m.mutate = (const(char)[] expr) { return `*((char*)0)='x';break;`; };
        break;
    case dcrCaseDel:
        // delete by commenting out
        m.mutate = (const(char)[] expr) { return format("/*%s*/", expr); };
        break;
    case lcrbAnd:
        m.mutate = (const(char)[] expr) { return "&"; };
        break;
    case lcrbOr:
        m.mutate = (const(char)[] expr) { return "|"; };
        break;
    case lcrbAndAssign:
        m.mutate = (const(char)[] expr) { return "&="; };
        break;
    case lcrbOrAssign:
        m.mutate = (const(char)[] expr) { return "|="; };
        break;
    }

    return m;
}

private:
@safe:

import dextool.plugin.mutate.backend.type : Offset, Mutation;

struct MutateImpl {
    alias CallbackTop = string delegate() @safe;
    alias CallbackMut = string delegate(const(char)[] from) @safe;

    /// Called before any other data has been written to the file.
    CallbackTop top;

    /// Called at the mutation point.
    CallbackMut mutate;
}

immutable string preambleAbs;

shared static this() {
    // this is ugly but works for now
    preambleAbs = `
#ifndef DEXTOOL_INJECTED_ABS_FUNCTION
#define DEXTOOL_INJECTED_ABS_FUNCTION
namespace {
template<typename T>
T abs_dextool(T v) { return v < 0 ? -v : v; }
template<typename T>
T fail_on_zero_dextool(T v) { if (v == 0) { *((char*)0)='x'; }; return v; }
}
#endif
`;
}

auto drop(T = void[])(T content, const Offset offset) {
    return DropRange!T(content[0 .. offset.begin], content[offset.end .. $]);
}

struct DropRange(T) {
    private {
        T[2] data;
        size_t idx;
    }

    this(T d0, T d1) {
        data = [d0, d1];
    }

    T front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return data[idx];
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        ++idx;
    }

    bool empty() @safe pure nothrow const @nogc {
        return idx == data.length;
    }
}
