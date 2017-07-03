/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.compiledb.frontend;

import std.algorithm : joiner;
import std.array : array;
import std.exception;

import logger = std.experimental.logger;

import dextool.compilation_db : CompileCommandDB, CompileCommandFilter,
    defaultCompilerFilter, parseFlag, fromArgCompileDb;
import dextool.type : AbsolutePath, ExitStatusType, FileName;

ExitStatusType doCompileDb(T)(ref T args) /*nothrow*/ {
    CompileCommandDB compile_db;
    try {
        compile_db = args.inCoompileDb.fromArgCompileDb;
    }
    catch (ErrnoException ex) {
        logger.error(ex.msg);
        return ExitStatusType.Errors;
    }

    auto out_db = makeOutputFilename(args.out_);
    writeDb(compile_db, out_db);

    return ExitStatusType.Ok;
}

AbsolutePath makeOutputFilename(string out_) {
    import std.file : isDir, FileException;
    import std.path : buildPath;

    try {
        if (out_.isDir) {
            return AbsolutePath(FileName(buildPath(out_, "compile_commands.json")));
        }
    }
    catch (FileException ex) {
    }

    return AbsolutePath(FileName(out_));
}

void writeDb(ref CompileCommandDB db, AbsolutePath dst) {
    import std.stdio : File;

    auto fout = File(dst, "w");

    auto flag_filter = CompileCommandFilter(defaultCompilerFilter.filter.dup, 0);
    logger.trace(flag_filter);

    void writeEntry(T)(ref const T e) {
        import std.exception : assumeUnique;
        import std.json : JSONValue;
        import std.utf : byChar;

        string raw_flags = assumeUnique(e.parseFlag(flag_filter).flags.joiner(" ").byChar.array());
        string abs_cmd = JSONValue(raw_flags).toString;

        fout.writefln(`  "directory": "%s",`, cast(string) e.directory);
        fout.writeln(`  "command": `, abs_cmd, ",");
        fout.writefln(`  "file": "%s"`, cast(string) e.absoluteFile);
    }

    if (db.length == 0) {
        return;
    }

    fout.writeln("[");

    foreach (ref const e; db[0 .. $ - 1]) {
        fout.writeln(" {");
        writeEntry(e);
        fout.writeln(" },");
    }

    fout.writeln(" {");
    writeEntry(db[$ - 1]);
    fout.writeln(" }");

    fout.writeln("]");
}
