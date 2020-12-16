/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module contains tools for testing where a sandbox is needed for creating
temporary files.
*/
module my.test;

import std.path : buildPath, baseName;
import std.format : format;

import my.path;

private AbsolutePath tmpDir() {
    import std.file : thisExePath;
    import std.path : dirName;

    return buildPath(thisExePath.dirName, "test_area").AbsolutePath;
}

TestArea makeTestArea(string name, string file = __FILE__) {
    return TestArea(buildPath(file.baseName, name));
}

struct ExecResult {
    int status;
    string output;
}

struct TestArea {
    import std.file : rmdirRecurse, mkdirRecurse, exists, readText, chdir;
    import std.process : wait;
    import std.stdio : File, stdin;
    static import std.process;

    const AbsolutePath sandboxPath;
    private int commandLogCnt;

    private AbsolutePath root;
    private bool chdirToRoot;

    this(string name) {
        root = AbsolutePath(".");
        sandboxPath = buildPath(tmpDir, name).AbsolutePath;

        if (exists(sandboxPath)) {
            rmdirRecurse(sandboxPath);
        }
        mkdirRecurse(sandboxPath);
    }

    ~this() {
        if (chdirToRoot) {
            chdir(root);
        }
    }

    /// Change current working directory to the sandbox. It is reset in the dtor.
    void chdirToSandbox() {
        chdirToRoot = true;
        chdir(sandboxPath);
    }

    /// Execute a command in the sandbox.
    ExecResult exec(Args...)(auto ref Args args_) {
        string[] args;
        static foreach (a; args_)
            args ~= a;

        const log = inSandbox(format!"command%s.log"(commandLogCnt++).Path);

        int exitCode = 1;
        try {
            auto fout = File(log, "w");
            fout.writefln("%-(%s %)", args);

            exitCode = std.process.spawnProcess(args, stdin, fout, fout, null,
                    std.process.Config.none, sandboxPath).wait;
            fout.writeln("exit code: ", exitCode);
        } catch (Exception e) {
        }
        return ExecResult(exitCode, readText(log));
    }

    ExecResult exec(string[] args, string[string] env) {
        const log = inSandbox(format!"command%s.log"(commandLogCnt++).Path);

        int exitCode = 1;
        try {
            auto fout = File(log, "w");
            fout.writefln("%-(%s %)", args);

            exitCode = std.process.spawnProcess(args, stdin, fout, fout, env,
                    std.process.Config.none, sandboxPath).wait;
            fout.writeln("exit code: ", exitCode);
        } catch (Exception e) {
        }
        return ExecResult(exitCode, readText(log));
    }

    Path inSandbox(string fileName) @safe pure nothrow const {
        return sandboxPath ~ fileName;
    }
}

void dirContentCopy(Path src, Path dst) {
    import std.algorithm;
    import std.file;
    import std.path;
    import my.file;

    assert(src.isDir);
    assert(dst.isDir);

    foreach (f; dirEntries(src, SpanMode.shallow).filter!"a.isFile") {
        auto dst_f = buildPath(dst, f.name.baseName).Path;
        copy(f.name, dst_f);
        if (isExecutable(Path(f.name)))
            setExecutable(dst_f);
    }
}

auto regexIn(T)(string rawRegex, T[] array, string file = __FILE__, in size_t line = __LINE__) {
    import std.regex : regex, matchFirst;

    auto r = regex(rawRegex);

    foreach (v; array) {
        if (!matchFirst(v, r).empty)
            return;
    }

    import unit_threaded.exception : fail;

    fail(formatValueInItsOwnLine("Value ",
            rawRegex) ~ formatValueInItsOwnLine("not in ", array), file, line);
}

auto regexNotIn(T)(string rawRegex, T[] array, string file = __FILE__, in size_t line = __LINE__) {
    import std.regex : regex, matchFirst;
    import unit_threaded.exception : fail;

    auto r = regex(rawRegex);

    foreach (v; array) {
        if (!matchFirst(v, r).empty) {
            fail(formatValueInItsOwnLine("Value ",
                    rawRegex) ~ formatValueInItsOwnLine("in ", array), file, line);
            return;
        }
    }
}

string[] formatValueInItsOwnLine(T)(in string prefix, scope auto ref T value) {
    import std.conv : to;
    import std.traits : isSomeString;
    import std.range.primitives : isInputRange;
    import std.traits; // too many to list
    import std.range; // also

    static if (isSomeString!T) {
        // isSomeString is true for wstring and dstring,
        // so call .to!string anyway
        return [prefix ~ `"` ~ value.to!string ~ `"`];
    } else static if (isInputRange!T) {
        return formatRange(prefix, value);
    } else {
        return [prefix ~ convertToString(value)];
    }
}

string[] formatRange(T)(in string prefix, scope auto ref T value) {
    import std.conv : text;
    import std.range : ElementType;
    import std.algorithm : map, reduce, max;

    //some versions of `text` are @system
    auto defaultLines = () @trusted { return [prefix ~ value.text]; }();

    static if (!isInputRange!(ElementType!T))
        return defaultLines;
    else {
        import std.array : array;

        const maxElementSize = value.empty ? 0 : value.map!(a => a.array.length)
            .reduce!max;
        const tooBigForOneLine = (value.array.length > 5 && maxElementSize > 5)
            || maxElementSize > 10;
        if (!tooBigForOneLine)
            return defaultLines;
        return [prefix ~ "["] ~ value.map!(a => formatValueInItsOwnLine("              ",
                a).join("") ~ ",").array ~ "          ]";
    }
}
