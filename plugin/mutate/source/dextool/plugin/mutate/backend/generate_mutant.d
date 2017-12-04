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

import dextool.type : AbsolutePath, ExitStatusType;
import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    MutationId;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeOutput,
    ValidateLoc;
import dextool.plugin.mutate.type : MutationKind;

ExitStatusType runGenerateMutant(ref Database db, MutationKind kind,
        Nullable!long user_mutation, FilesysIO fio, ValidateLoc val_loc) @safe nothrow {
    import dextool.plugin.mutate.backend.utility : toInternal;

    Nullable!MutationEntry mutp;
    if (!user_mutation.isNull) {
        mutp = db.getMutation(MutationId(user_mutation.get));
        logger.error(mutp.isNull, "No such mutation id: ", user_mutation.get).collectException;
    } else {
        mutp = db.nextMutation(kind.toInternal);
    }
    if (mutp.isNull)
        return ExitStatusType.Errors;

    ubyte[] content;
    try {
        content = fio.makeInput(mutp.file).read;
        if (content.length == 0)
            return ExitStatusType.Errors;
    }
    catch (Exception e) {
        collectException(logger.error(e.msg));
        return ExitStatusType.Errors;
    }

    ExitStatusType exit_st;
    try {
        auto ofile = makeOutputFilename(val_loc, fio, mutp.file);
        auto fout = fio.makeOutput(ofile);
        auto res = generateMutant(db, mutp, content, fout);
        exit_st = res.status;
        if (res.status == ExitStatusType.Ok)
            logger.infof("%s Mutate from '%s' to '%s' in %s", mutp.id, res.from, res.to, ofile);
    }
    catch (Exception e) {
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
    ExitStatusType status;
    const(char)[] from;
    const(char)[] to;
}

auto generateMutant(ref Database db, MutationEntry mutp, const(ubyte)[] content, ref SafeOutput fout) @safe {
    import dextool.plugin.mutate.backend.utility : checksum;

    auto db_checksum = db.getFileChecksum(mutp.file);
    auto f_checksum = checksum(cast(const(ubyte)[]) content);
    if (db_checksum.isNull) {
        logger.errorf("Database contains erronious data. A mutation point for %s exist but the file has no checksum",
                mutp.file);
        return GenerateMutantResult(ExitStatusType.Errors);
    } else if (db_checksum != f_checksum) {
        logger.errorf(
                "Unable to mutate %s (%s%s) because the checksum is different from the one in the database (%s%s)",
                mutp.file, f_checksum.c0, f_checksum.c1, db_checksum.c0, db_checksum.c1);
        return GenerateMutantResult(ExitStatusType.Errors);
    }

    const auto from_ = () {
        return cast(const(char)[]) content[mutp.mp.offset.begin .. mutp.mp.offset.end];
    }();

    auto mut = makeMutation(mutp.mp.mutations[0].kind);

    // #SPC-plugin_mutate_file_security-header_as_warning
    fout.write("/* DEXTOOL: THIS FILE IS MUTATED */\n");

    mut.top(fout);
    auto s = content.drop(mutp.mp.offset);
    fout.write(s.front);
    s.popFront;
    const string to_ = mut.mutate(from_);
    fout.write(to_);
    fout.write(s.front);

    return GenerateMutantResult(ExitStatusType.Ok, from_, to_);
}

private:
@safe:

import dextool.plugin.mutate.backend.type : Offset, Mutation;

struct MutateImpl {
    alias CallbackTop = void function(ref SafeOutput f) @safe;
    alias CallbackMut = string function(const(char)[] from) @safe;

    /// Called before any other data has been written to the file.
    CallbackTop top = (ref SafeOutput) {  };

    /// Called at the mutation point.
    CallbackMut mutate = (const(char)[] from) { return null; };
}

auto makeMutation(Mutation.Kind kind) {
    import std.stdio : File;

    MutateImpl m;

    final switch (kind) with (Mutation.Kind) {
        /// the kind is not initialized thus can only ignore the point
    case none:
        break;
        /// Relational operator replacement
    case rorLT:
        m.mutate = (const(char)[] expr) { return ("<"); };
        break;
    case rorLE:
        m.mutate = (const(char)[] expr) { return "<="; };
        break;
    case rorGT:
        m.mutate = (const(char)[] expr) { return ">"; };
        break;
    case rorGE:
        m.mutate = (const(char)[] expr) { return ">="; };
        break;
    case rorEQ:
        m.mutate = (const(char)[] expr) { return "=="; };
        break;
    case rorNE:
        m.mutate = (const(char)[] expr) { return "!="; };
        break;
        /// Logical connector replacement
    case lcrAnd:
        m.mutate = (const(char)[] expr) { return "&&"; };
        break;
    case lcrOr:
        m.mutate = (const(char)[] expr) { return "||"; };
        break;
        /// Arithmetic operator replacement
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
    case absPos:
        m.top = (ref SafeOutput a) { a.write(preambleAbs); };
        m.mutate = (const(char)[] b) { return format("dextool_abs(%s)", b); };
        break;
    case absNeg:
        m.top = (ref SafeOutput a) { a.write(preambleAbs); };
        m.mutate = (const(char)[] b) { return format("-dextool_abs(%s)", b); };
        break;
    case absZero:
        m.top = (ref SafeOutput a) { a.write(preambleAbs); };
        m.mutate = (const(char)[] b) { return "0"; };
        break;
    }

    return m;
}

import std.format : format;

string preambleAbs() {
    // this is ugly but works for now
    immutable abs_tmpl = `
#ifndef DEXTOOL_INJECTED_ABS_FUNCTION
#define DEXTOOL_INJECTED_ABS_FUNCTION
namespace {
template<typename T>
T dextool_abs(T v) { return v < 0 ? -v : v; }
}
#endif
`;
    return abs_tmpl;
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
