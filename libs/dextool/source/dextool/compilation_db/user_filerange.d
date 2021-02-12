/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This is a handy range to iterate over either all files from the user OR all
files in a compilation database.
*/
module dextool.compilation_db.user_filerange;

import logger = std.experimental.logger;
import std.algorithm : map, joiner;
import std.array : empty, appender, array;
import std.range : isInputRange, ElementType, only;
import std.typecons : tuple, Nullable;
import std.exception : collectException;

import dextool.compilation_db : CompileCommand, CompileCommandFilter,
    CompileCommandDB, parseFlag, ParseFlags, Compiler, SystemIncludePath;
import dextool.type : Path, AbsolutePath;

@safe:

struct SimpleRange(T) {
    private T[] values;

    this(T[] values) {
        this.values = values;
    }

    T front() {
        assert(!empty, "Can't get front of an empty range");
        return values[0];
    }

    void popFront() @safe pure nothrow @nogc {
        assert(!empty, "Can't pop front of an empty range");
        values = values[1 .. $];
    }

    bool empty() @safe pure nothrow const @nogc {
        import std.array : empty;

        return values.empty;
    }

    size_t length() @safe pure nothrow const @nogc {
        return values.length;
    }

    typeof(this) save() @safe pure nothrow {
        return typeof(this)(values);
    }

    static SimpleRange!T make(T[] values) {
        return SimpleRange!T(values);
    }
}

alias CompileCommandsRange = SimpleRange!CompileCommand;

/// Returns: a range over all files in the database.
CompileCommandsRange fileRange(CompileCommandDB db) {
    return CompileCommandsRange(db.payload);
}

CompileCommandsRange fileRange(Path[] files, Compiler compiler) {
    import std.file : getcwd;

    return CompileCommandsRange(files.map!(a => CompileCommand(a, AbsolutePath(a),
            AbsolutePath(Path(getcwd)), CompileCommand.Command([compiler]),
            Path.init, AbsolutePath.init)).array);
}

/// The flags in the CompileCommand are extracted and parsed.
struct ParsedCompileCommand {
    CompileCommand cmd;
    ParseFlags flags;
}

alias ParsedCompileCommandRange = SimpleRange!ParsedCompileCommand;

/// Returns: a range over all files in the range where the flags have been parsed.
auto parse(RangeT)(RangeT r, CompileCommandFilter ccFilter) @safe nothrow 
        if (is(ElementType!RangeT == CompileCommand)) {
    return r.map!(a => ParsedCompileCommand(a, parseFlag(a, ccFilter)));
}

/// Returns: a range wherein the system includes for the compiler has been
/// deduced and added to the `flags` data.
auto addSystemIncludes(RangeT)(RangeT r) @safe nothrow 
        if (is(ElementType!RangeT == ParsedCompileCommand)) {
    static SystemIncludePath[] deduce(CompileCommand cmd, Compiler compiler) @safe nothrow {
        import dextool.compilation_db.system_compiler : deduceSystemIncludes;

        try {
            return deduceSystemIncludes(cmd, compiler);
        } catch (Exception e) {
            logger.info(e.msg).collectException;
        }
        return SystemIncludePath[].init;
    }

    return r.map!((a) {
        a.flags.systemIncludes = deduce(a.cmd, a.flags.compiler);
        return a;
    });
}

/// Return: add a compiler to the `flags` data if it is missing.
auto addCompiler(RangeT)(RangeT r, Compiler compiler) @safe nothrow 
        if (is(ElementType!RangeT == ParsedCompileCommand)) {
    ParsedCompileCommand add(ParsedCompileCommand p, Compiler compiler) @safe nothrow {
        if (p.flags.compiler.empty) {
            p.flags.compiler = compiler;
        }
        return p;
    }

    return r.map!(a => add(a, compiler));
}

/// Return: replace the compiler in `flags` with `compiler` if `compiler` is
/// NOT empty.
auto replaceCompiler(RangeT)(RangeT r, Compiler compiler) @safe nothrow 
        if (is(ElementType!RangeT == ParsedCompileCommand)) {
    return r.map!((a) {
        if (!compiler.empty)
            a.flags.compiler = compiler;
        return a;
    });
}

struct LimitFileRange {
    /// Files not found in the compile_commands database;
    string[] missingFiles;

    ParsedCompileCommand[] commands;

    bool isMissingFilesEmpty() {
        return missingFiles.empty;
    }

    /// Returns: a range over all files that where found in the database.
    ParsedCompileCommandRange range() {
        return ParsedCompileCommandRange.make(commands);
    }
}

/// Returns: a struct which has extracted `onlyTheseFiles` into either using
/// the matching `ParsedCompileCommand` or missing.
LimitFileRange limitFileRange(ParsedCompileCommand[] db, string[] onlyTheseFiles) {
    import dextool.compilation_db;

    auto missing = appender!(string[])();
    auto app = appender!(ParsedCompileCommand[])();
    foreach (a; onlyTheseFiles.map!(a => tuple!("file", "result")(a, find(db, a)))) {
        if (a.result.isNull) {
            missing.put(a.file);
        } else {
            app.put(a.result.get);
        }
    }

    return LimitFileRange(missing.data, app.data);
}

LimitFileRange limitOrAllRange(T)(ParsedCompileCommand[] db, T[] onlyTheseFiles) {
    if (onlyTheseFiles.empty)
        return LimitFileRange(null, db);
    return limitFileRange(db, onlyTheseFiles.map!(a => cast(string) a).array);
}

/// Returns: prepend all CompileCommands parsed flags with `flags`.
auto prependFlags(RangeT)(RangeT r, string[] flags)
        if (isInputRange!RangeT && is(ElementType!RangeT == ParsedCompileCommand)) {
    return r.map!((a) { a.flags.prependCflags(flags); return a; });
}

/** Find a best matching compile_command in the database against the path
 * pattern `glob`.
 *
 * When searching for the compile command for a file, the compilation db can
 * return several commands, as the file may have been compiled with different
 * options in different parts of the project.
 *
 * Params:
 *  glob = glob pattern to find a matching file in the DB against
 */
Nullable!ParsedCompileCommand find(ParsedCompileCommand[] db, string glob) @safe {
    import dextool.compilation_db : isMatch;

    foreach (a; db) {
        if (isMatch(a.cmd, glob))
            return typeof(return)(a);
    }
    return typeof(return).init;
}
