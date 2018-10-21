/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html;

import logger = std.experimental.logger;

import dextool.type : AbsolutePath, Path, DirName;
import dextool.plugin.mutate.backend.database : Database, FileRow,
    FileMutantRow, MutationId;
import dextool.plugin.mutate.backend.report.utility : toSections;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel,
    ReportSection;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : FileReport, FilesReporter;
import dextool.plugin.mutate.backend.type : Mutation, Offset, SourceLoc;
import dextool.plugin.mutate.config : ConfigReport;

import dextool.plugin.mutate.backend.report.html.tmpl;
import dextool.plugin.mutate.backend.report.html.js;

version (unittest) {
    import unit_threaded : shouldEqual;
}

struct FileIndex {
    Path path;
    string display;
}

@safe final class ReportHtml : FileReport, FilesReporter {
    import std.array : Appender;
    import std.stdio : File, writefln, writeln;
    import std.xml : encode;
    import dextool.set;

    immutable htmlExt = ".html";
    immutable htmlDir = "html";

    const Mutation.Kind[] kinds;
    const ConfigReport conf;
    const AbsolutePath logDir;
    MutationKind[] humanReadableKinds;
    Set!ReportSection sections;
    FilesysIO fio;

    // all files that have been produced.
    Appender!(FileIndex[]) files;

    // the context for the file that is currently being processed.
    FileCtx ctx;

    this(const Mutation.Kind[] kinds, const ConfigReport conf, FilesysIO fio) {
        import std.path : buildPath;

        this.kinds = kinds;
        this.fio = fio;
        this.conf = conf;
        this.logDir = buildPath(conf.logDir, htmlDir).Path.AbsolutePath;

        sections = (conf.reportSection.length == 0 ? conf.reportLevel.toSections
                : conf.reportSection.dup).setFromList;
    }

    override void mutationKindEvent(const MutationKind[] k) {
        import std.file : mkdirRecurse;

        humanReadableKinds = k.dup;
        mkdirRecurse(this.logDir);
    }

    override FileReport getFileReportEvent(ref Database db, const ref FileRow fr) {
        import std.algorithm : joiner;
        import std.path : pathSplitter, buildPath;
        import std.stdio : File;
        import std.utf : toUTF8;

        const original = fr.file.dup.pathSplitter.joiner("_").toUTF8;
        const report = (original ~ htmlExt).Path;
        files.put(FileIndex(report, fr.file));

        const out_path = buildPath(logDir, report).Path.AbsolutePath;

        ctx = FileCtx.init;
        ctx.processFile = fr.file;
        ctx.out_ = File(out_path, "w");
        ctx.span = Spanner(tokenize(fio.getOutputDir, fr.file));

        ctx.out_.writefln(htmlBegin, encode(original));
        ctx.out_.writeln(htmlBegin2);

        return this;
    }

    override void fileMutantEvent(const ref FileMutantRow fr) {
        import dextool.plugin.mutate.backend.utility : makeMutationText;

        // TODO unnecessary to create the mutation text here.
        // Move it to endFileEvent. This is inefficient.

        auto fin = fio.makeInput(AbsolutePath(ctx.processFile, DirName(fio.getOutputDir)));
        auto txt = makeMutationText(fin, fr.mutationPoint.offset, fr.mutation.kind, fr.lang);
        ctx.span.put(FileMutant(fr.id, fr.mutationPoint.offset,
                txt.original.idup, txt.mutation.idup, fr.mutation.status));
    }

    override void endFileEvent() {
        import std.algorithm : max, each, map, min, canFind;
        import std.array : appender;
        import std.conv : to;
        import std.format : format;
        import std.range : repeat;

        static struct MData {
            MutationId id;
            FileMutant.Text txt;
            Mutation.Status status;
        }

        Set!MutationId ids;
        auto muts = appender!(MData[])();
        int line = 1;
        int column = 1;

        foreach (const s; ctx.span.toRange) {
            if (s.tok.loc.line > line)
                column = 1;

            "<br>".repeat(max(0, s.tok.loc.line - line)).each!(a => ctx.out_.writeln(a));
            const spaces = max(0, s.tok.loc.column - column);
            if (spaces > 1)
                "&nbsp;".repeat(spaces).each!(a => ctx.out_.write(a));
            ctx.out_.writeln(`<div style="display: inline;">`);
            ctx.out_.writefln(`<span class="original %s %s %(mutid%s %)">%s</span>`,
                    s.tok.toName, s.muts.canFind!((a,
                        b) => a.status == b)(Mutation.Status.alive) ? "status_alive"
                    : null, s.muts.map!(a => a.id), encode(s.tok.spelling));

            foreach (m; s.muts) {
                if (!ids.contains(m.id)) {
                    ids.add(m.id);
                    muts.put(MData(m.id, m.txt, m.status));
                    const org = m.original.encode;
                    const mut = m.mutation.encode;
                    ctx.out_.writefln(`<span id="%s" onmouseenter="fly(event, '%s')" onmouseleave="fly(event, '%s')" class="mutant %s">%s</span>`,
                            m.id, org, org, s.tok.toName, mut);
                    ctx.out_.writefln(`<a href="#%s"></a>`, m.id);
                }
            }
            ctx.out_.writeln(`</div>`);

            line = s.tok.locEnd.line;
            column = s.tok.locEnd.column;
        }

        ctx.out_.writeln("<script>");
        ctx.out_.writefln("var g_mutids = [%(%s,%)];", muts.data.map!(a => a.id));
        ctx.out_.writefln("var g_muts_orgs = [%(%s,%)];",
                muts.data.map!(a => a.txt.original[0 .. min(5, a.txt.original.length)]));
        ctx.out_.writefln("var g_muts_muts = [%(%s,%)];",
                muts.data.map!(a => a.txt.mutation[0 .. min(5, a.txt.mutation.length)]));
        ctx.out_.writefln("var g_muts_st = [%(%s,%)];", muts.data.map!(a => a.status.to!string));
        ctx.out_.writeln("</script>");
        ctx.out_.writefln(htmlEnd, js_file);
    }

    override void postProcessEvent(ref Database db) {
        import std.algorithm : splitter;
        import std.datetime : Clock;
        import std.path : buildPath;
        import dextool.plugin.mutate.backend.report.utility : reportStatistics;

        const index_f = buildPath(logDir, "index" ~ htmlExt);
        auto index = File(index_f, "w");

        index.writefln(`<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html;charset=UTF-8">
<title>Mutation Testing Report %(%s %) %s</title>
</head>
<style>body {font-family: monospace; font-size: 14px;}</style>
`, humanReadableKinds, Clock.currTime);

        auto stats = reportStatistics(db, kinds);
        index.writeln(`<table>`);
        foreach (l; stats.toString.splitter('\n'))
            index.writefln(`<tr><td>%s</td></tr>`, encode(l));
        index.writeln(`</table>`);

        foreach (f; files.data) {
            index.writefln(`<p><a href="%s">%s</a></p>`, f.path, encode(f.display));
        }

        index.writeln(`</body></html>`);
    }

    override void endEvent(ref Database) {
    }
}

@safe:
private:

struct FileCtx {
    import std.stdio;

    Path processFile;
    File out_;

    Spanner span;
}

struct Token {
    import clang.c.Index : CXTokenKind;

    CXTokenKind kind;
    Offset offset;
    SourceLoc loc;
    SourceLoc locEnd;
    string spelling;

    string toId() @safe const {
        import std.format : format;

        return format("%s-%s", offset.begin, offset.end);
    }

    string toName() @safe const {
        import std.conv : to;

        return kind.to!string;
    }

    int opCmp(ref const typeof(this) s) const @safe {
        if (offset.begin > s.offset.begin)
            return 1;
        if (offset.begin < s.offset.begin)
            return -1;
        if (offset.end > s.offset.end)
            return 1;
        if (offset.end < s.offset.end)
            return -1;
        return 0;
    }
}

@("shall be possible to construct in @safe")
@safe unittest {
    import clang.c.Index : CXTokenKind;

    auto tok = Token(CXTokenKind.comment, Offset(1, 2), SourceLoc(1, 2), SourceLoc(1, 2), "smurf");
}

// This is a bit slow, I think. Optimize by reducing the created strings.
// trusted: none of the unsafe accessed data escape this function.
auto tokenize(AbsolutePath base_dir, Path f) @trusted {
    import std.array : appender;
    import std.path : buildPath;
    import std.typecons : Yes;
    import clang.Index;
    import clang.TranslationUnit;
    import cpptooling.analyzer.clang.context;

    const fpath = buildPath(base_dir, f);

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto tu = ctx.makeTranslationUnit(fpath);

    auto toks = appender!(Token[])();
    foreach (ref t; tu.cursor.tokens) {
        auto ext = t.extent;
        auto start = ext.start;
        auto end = ext.end;
        toks.put(Token(t.kind, Offset(start.offset, end.offset),
                SourceLoc(start.line, start.column), SourceLoc(end.line, end.column), t.spelling));
    }

    return toks.data;
}

struct FileMutant {
    static struct Text {
        /// the original text that covers the offset.
        string original;
        /// The mutation text that covers the offset.
        string mutation;
    }

    MutationId id;
    Offset offset;
    Text txt;
    Mutation.Status status;

    this(MutationId id, Offset offset, string original, string mutation, Mutation.Status st) {
        this.id = id;
        this.offset = offset;
        this.txt.original = original;
        this.txt.mutation = mutation;
        this.status = st;
    }

    this(MutationId id, Offset offset, string original) {
        this(id, offset, original, null, Mutation.Status.init);
    }

    string original() @safe pure nothrow const @nogc scope {
        return txt.original;
    }

    string mutation() @safe pure nothrow const @nogc scope {
        return txt.mutation;
    }

    int opCmp(ref const typeof(this) s) const @safe {
        if (offset.begin > s.offset.begin)
            return 1;
        if (offset.begin < s.offset.begin)
            return -1;
        if (offset.end > s.offset.end)
            return 1;
        if (offset.end < s.offset.end)
            return -1;
        return 0;
    }
}

@("shall be possible to construct a FileMutant in @safe")
@safe unittest {
    auto fmut = FileMutant(MutationId(1), Offset(1, 2), "smurf");
}

/*
I get a mutant that have a start/end offset.
I have all tokens.
I can't write the html before I have all mutants for the offset.
Hmm potentially this mean that I can't write any html until I have analyzed all mutants for the file.
This must be so....

How to do it?

From reading https://stackoverflow.com/questions/11389627/span-overlapping-strings-in-a-paragraph
it seems that generating a <span..> for each token with multiple classes in them. A class for each mutant.
then they can be toggled on/off.

a <href> tag to the beginning to jump to the mutant.
*/

/** Provide an interface to travers the tokens and get the overlapping mutants.
 */
struct Spanner {
    import std.container : RedBlackTree, redBlackTree;
    import std.range : isOutputRange;

    alias BTree(T) = RedBlackTree!(T, "a < b", true);

    BTree!Token tokens;
    BTree!FileMutant muts;

    this(Token[] tokens) @trusted {
        this.tokens = new typeof(this.tokens);
        this.muts = new typeof(this.muts)();

        this.tokens.insert(tokens);
    }

    void put(const FileMutant fm) {
        muts.insert(fm);
    }

    SpannerRange toRange() @safe {
        return SpannerRange(tokens, muts);
    }

    string toString() @safe pure const {
        import std.array : appender;

        auto buf = appender!string;
        this.toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;
        import std.range : put, zip, StoppingPolicy;
        import std.string;
        import std.algorithm : max;
        import std.traits : Unqual;

        ulong sz;

        foreach (ref const t; zip(StoppingPolicy.longest, tokens[], muts[])) {
            auto c0 = format("%s", cast(Unqual!(typeof(t[0]))) t[0]);
            string c1;
            if (t[1] != typeof(t[1]).init)
                c1 = format("%s", cast(Unqual!(typeof(t[1]))) t[1]);
            sz = max(sz, c0.length, c1.length);
            formattedWrite(w, "%s | %s\n", c0.rightJustify(sz), c1);
        }
    }
}

@("shall be possible to construct a Spanner in @safe")
@safe unittest {
    import std.algorithm;
    import std.conv;
    import std.range;
    import clang.c.Index : CXTokenKind;

    auto toks = zip(iota(10), iota(10, 20)).map!(a => Token(CXTokenKind.comment,
            Offset(a[0], a[1]), SourceLoc.init, SourceLoc.init, a[0].to!string)).retro.array;
    auto span = Spanner(toks);

    span.put(FileMutant(MutationId(1), Offset(1, 10), "smurf"));
    span.put(FileMutant(MutationId(1), Offset(9, 15), "donkey"));

    // TODO add checks
}

/**
 *
 * # Overlap Cases
 * 1. Perfekt overlap
 * |--T--|
 * |--M--|
 *
 * 2. Token enclosing mutant
 * |---T--|
 *   |-M-|
 *
 * 3. Mutant beginning inside a token
 * |---T--|
 *   |-M----|
 *
 * 4. Mutant overlapping multiple tokens.
 * |--T--|--T--|
 * |--M--------|
 */
struct SpannerRange {
    alias BTree = Spanner.BTree;

    BTree!Token tokens;
    BTree!FileMutant muts;

    this(BTree!Token tokens, BTree!FileMutant muts) @safe {
        this.tokens = tokens;
        this.muts = muts;
        dropMutants;
    }

    Span front() @safe pure nothrow {
        import std.array : appender;

        assert(!empty, "Can't get front of an empty range");
        auto t = tokens.front;
        if (muts.empty)
            return Span(t);

        auto app = appender!(FileMutant[])();
        foreach (m; muts) {
            if (m.offset.begin < t.offset.end)
                app.put(m);
            else
                break;
        }

        return Span(t, app.data);
    }

    void popFront() @safe {
        assert(!empty, "Can't pop front of an empty range");
        tokens.removeFront;
        dropMutants;
    }

    bool empty() @safe pure nothrow @nogc {
        return tokens.empty;
    }

    private void dropMutants() @safe {
        import std.algorithm : filter;
        import std.array : array;

        if (tokens.empty)
            return;

        // removing mutants that the tokens have "passed by"
        const t = tokens.front;
        auto r = muts[].filter!(a => a.offset.end <= t.offset.begin).array;
        muts.removeKey(r);
    }
}

struct Span {
    import std.range : isOutputRange;

    Token tok;
    FileMutant[] muts;

    string toString() @safe pure const {
        import std.array : appender;
        import std.format : FormatSpec;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;
        import std.range : put;

        formattedWrite(w, "%s|%(%s %)", tok, muts);
    }
}

@("shall return a range grouping mutants by the tokens they overlap")
@safe unittest {
    import std.algorithm;
    import std.array : array;
    import std.conv;
    import std.range;
    import clang.c.Index : CXTokenKind;

    auto offsets = zip(iota(0, 150, 10), iota(10, 160, 10)).map!(a => Offset(a[0], a[1])).array;

    auto toks = offsets.map!(a => Token(CXTokenKind.comment, a, SourceLoc.init,
            SourceLoc.init, a.begin.to!string)).retro.array;
    auto span = Spanner(toks);

    span.put(FileMutant(MutationId(2), Offset(11, 15), "token enclosing mutant"));
    span.put(FileMutant(MutationId(3), Offset(31, 42), "mutant beginning inside a token"));
    span.put(FileMutant(MutationId(4), Offset(50, 80), "mutant overlapping multiple tokens"));

    span.put(FileMutant(MutationId(5), Offset(90, 100), "1 multiple mutants for a token"));
    span.put(FileMutant(MutationId(6), Offset(90, 110), "2 multiple mutants for a token"));
    span.put(FileMutant(MutationId(1), Offset(120, 130), "perfect overlap"));

    auto res = span.toRange.array;
    //logger.tracef("%(%s\n%)", res);
    res[1].muts[0].id.shouldEqual(2);
    res[2].muts.length.shouldEqual(0);
    res[3].muts[0].id.shouldEqual(3);
    res[4].muts[0].id.shouldEqual(3);
    res[5].muts[0].id.shouldEqual(4);
    res[6].muts[0].id.shouldEqual(4);
    res[7].muts[0].id.shouldEqual(4);
    res[8].muts.length.shouldEqual(0);
    res[9].muts.length.shouldEqual(2);
    res[9].muts[0].id.shouldEqual(5);
    res[9].muts[1].id.shouldEqual(6);
    res[10].muts[0].id.shouldEqual(6);
    res[11].muts.length.shouldEqual(0);
    res[12].muts[0].id.shouldEqual(1);
    res[13].muts.length.shouldEqual(0);
}
