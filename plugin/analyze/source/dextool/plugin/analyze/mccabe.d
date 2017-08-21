/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.analyze.mccabe;

import logger = std.experimental.logger;

import dextool.type : ExitStatusType, FileName, AbsolutePath;

struct Function {
    import cpptooling.data.type : CFunctionName;

    CFunctionName name;

    AbsolutePath file;
    uint line;
    uint column;

    int complexity;

    nothrow @safe size_t toHash() {
        import std.digest.digest;
        import std.digest.crc;

        auto hash = makeDigest!CRC32();
        () @trusted{
            hash.put(cast(ubyte[]) cast(string) file);
            hash.put(cast(ubyte[]) cast(string) name);
        }();
        hash.finish;

        auto h = hash.peek();
        return line ^ column ^ (h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]);
    }

    bool opEquals(const this o) @safe pure nothrow const @nogc {
        return name == o.name && file == o.file && line == o.line && column == o.column;
    }

    int opCmp(const this rhs) @safe pure nothrow const {
        // dfmt off
        if (name < rhs.name)
            return -1;
        else if (name > rhs.name)
            return 1;
        if (file < rhs.file)
            return -1;
        else if (file > rhs.file)
            return 1;
        if (line < rhs.line)
            return -1;
        else if (line > rhs.line)
            return 1;
        if (column < rhs.column)
            return -1;
        else if (column > rhs.column)
            return 1;
        return this == rhs ? 0 : 1;
        // dfmt on
    }
}

struct File {
    AbsolutePath file;
    int complexity;
}

struct McCabeResult {
    import std.container : RedBlackTree;

    RedBlackTree!Function functions;
    File[AbsolutePath] files;

    static auto make() {
        import std.container : make;

        return McCabeResult(make!(RedBlackTree!Function)(), null);
    }

    /**
     * Returns: if the function where added.
     */
    void put(Function func) @safe {
        // unsafe in dmd-2.071.1 but safe in 2.075.0
        auto insert_nr = () @trusted{ return functions.insert(func); }();

        if (insert_nr == 1) {
            // files that are inserted are thus unique in the analyze.
            // it is thus OK to add the mccabe to the file count.

            if (auto f = func.file in files) {
                f.complexity += func.complexity;
            } else {
                files[func.file] = File(func.file, func.complexity);
            }
        }
    }
}

struct McCabe {
    import std.typecons : NullableRef;

    private NullableRef!McCabeResult result;

    this(ref McCabeResult result) {
        this.result = &result;
    }

    void analyze(T)(const(T) v) @safe {
        auto c = v.cursor;

        if (!c.isDefinition) {
            return;
        }

        auto mccabe = () @trusted{
            import dextool.plugin.analyze.cpp_clang_extension;

            return calculate(c.cx);
        }();

        if (!mccabe.hasValue || mccabe.value == 0)
            return;

        import clang.SourceLocation : toString;

        auto loc = c.location;
        auto file_under_analyze = AbsolutePath(FileName(loc.file.toString));

        import cpptooling.data.type : CFunctionName;

        result.put(Function(CFunctionName(c.spelling), file_under_analyze,
                loc.line, loc.column, mccabe.value));
    }
}

void resultToStdout(McCabeResult analyze, int threshold) {
    import std.algorithm : map, filter;
    import std.array : byPair;
    import std.range : tee;
    import std.stdio : writeln, writefln;

    // the |==... is used to make it easy to filter with unix tools. It makes
    // it so that sort -h will not mix it with the numbers.

    long total;

    writeln("McCabe Cyclomatic Complexity");
    writeln("|======File");
    foreach (f; analyze.files.byPair.map!(a => a[1])
            .tee!(a => total += a.complexity).filter!(a => a.complexity >= threshold)) {
        writefln("%-6s %s", f.complexity, f.file);
    }
    writeln("|======Total McCabe ", total);
    writeln("|======Function");
    foreach (f; analyze.functions[].filter!(a => a.complexity >= threshold))
        writefln("%-6s %s [%s line=%s column=%s]", f.complexity,
                cast(string) f.name, cast(string) f.file, f.line, f.column);

    if (analyze.files.length == 0 && analyze.functions.length == 0) {
        writeln("No result. Did you forget --restrict?");
    }
}

void resultToJson(AbsolutePath fname, McCabeResult analyze, int threshold) {
    import std.ascii : newline;
    import std.algorithm : map, filter;
    import std.array : byPair;

    static import std.stdio;

    auto fout = std.stdio.File(cast(string) fname, "w");

    fout.writeln(`{"kind": "files",`);
    fout.write(` "values":[`);
    long total;
    bool add_comma;
    foreach (f; analyze.files.byPair.map!(a => a[1])) {
        if (add_comma) {
            fout.writeln(",");
        } else {
            add_comma = true;
            fout.writeln;
        }
        fout.writefln(` {"file":"%s",`, cast(string) f.file);
        fout.writefln(`  "mccabe":%s`, f.complexity);
        fout.write(" }");
        total += f.complexity;
    }
    fout.writeln(newline, " ],");
    fout.writefln(` "total_mccabe":%s`, total);
    fout.writeln("},");

    fout.writeln(`{"kind": "functions",`);
    fout.write(` "values":[`);
    add_comma = false;
    foreach (f; analyze.functions[].filter!(a => a.complexity >= threshold)) {
        if (add_comma) {
            fout.writeln(",");
        } else {
            add_comma = true;
            fout.writeln;
        }
        fout.writefln(` {"function":"%s",`, cast(string) f.name);
        fout.writefln(`  "location": { "file":"%s", "line":%s, "column":%s },`,
                cast(string) f.file, f.line, f.column);
        fout.writefln(`  "mccabe":%s`, f.complexity);
        fout.write(" }");
    }

    fout.writeln(newline, " ]");
    fout.writeln("}");
}
