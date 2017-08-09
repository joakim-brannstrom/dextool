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
        if (file < rhs.file)
            return -1;
        if (line < rhs.line)
            return -1;
        if (column < rhs.column)
            return -1;
        return this == rhs ? 0 : 1;
        // dfmt on
    }
}

struct File {
    AbsolutePath file;
    int complexity;
}

class McCabe {
    import std.container : RedBlackTree;
    import cpptooling.analyzer.clang.ast : FunctionDecl;

    File[AbsolutePath] files;
    RedBlackTree!Function functions;

    private int threshold;

    this(int threshold) {
        import std.container : make;

        functions = make!(typeof(functions))();
        this.threshold = threshold;
    }

    void analyze(T)(const(T) v) @safe {
        import std.stdio : writefln;

        auto c = v.cursor;

        if (!c.isDefinition) {
            return;
        }

        auto loc = c.location;

        auto mccabe = () @trusted{
            import dextool.plugin.analyze.cpp_clang_extension;

            return calculate(c.cx);
        }();

        if (!mccabe.hasValue || mccabe.value == 0)
            return;

        import clang.SourceLocation : toString;

        auto file_under_analyze = AbsolutePath(FileName(loc.file.toString));

        import cpptooling.data.type : CFunctionName;

        // unsafe in dmd-2.071.1 but safe in 2.075.0
        auto insert_nr = () @trusted{
            return functions.insert(Function(CFunctionName(c.spelling),
                    file_under_analyze, loc.line, loc.column, mccabe.value));
        }();

        if (insert_nr == 1) {
            // a new function thus add it to the files sum
            if (auto f = file_under_analyze in files) {
                f.complexity += mccabe.value;
            } else {
                files[file_under_analyze] = File(file_under_analyze, mccabe.value);
            }
        }
    }
}

void writeResult(AbsolutePath fname, McCabe analyze) {
    import std.ascii : newline;
    import std.algorithm : map, filter;
    import std.array : byPair;
    import std.stdio;

    debug {
        logger.trace("Files:");
        foreach (f; analyze.files.byPair.map!(a => a[1]))
            logger.tracef("  McCabe:%s %s", f.complexity, f.file);
        logger.trace("Functions:");
        foreach (f; analyze.functions[].filter!(a => a.complexity >= analyze.threshold))
            logger.tracef("  McCabe:%s %s [%s line=%s column=%s]", f.complexity,
                    cast(string) f.name, cast(string) f.file, f.line, f.column);
    }

    auto fout = std.stdio.File(cast(string) fname, "w");

    fout.write("[");
    bool add_comma;
    foreach (f; analyze.files.byPair.map!(a => a[1])) {
        if (add_comma) {
            fout.writeln(",");
        } else {
            add_comma = true;
            fout.writeln;
        }
        fout.writeln(" {");
        fout.writefln(`  "file":"%s",`, cast(string) f.file);
        fout.writefln(`  "mccabe":%s`, f.complexity);
        fout.write(" }");
    }
    fout.writeln(newline, "]");

    fout.write("[");
    add_comma = false;
    foreach (f; analyze.functions[].filter!(a => a.complexity >= analyze.threshold)) {
        if (add_comma) {
            fout.writeln(",");
        } else {
            add_comma = true;
            fout.writeln;
        }
        fout.writeln(" {");
        fout.writefln(`  "function":"%s",`, cast(string) f.name);
        fout.writefln(`  "location": { "file":"%s", "line":%s, "column":%s },`,
                cast(string) f.file, f.line, f.column);
        fout.writefln(`  "mccabe":%s`, f.complexity);
        fout.write(" }");
    }

    fout.writeln(newline, "]");
}
