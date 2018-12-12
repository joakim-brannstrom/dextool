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
import std.exception : collectException;
import std.format : format;
import std.stdio : File;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database, FileRow, FileMutantRow, MutationId;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : FileReport, FilesReporter;
import dextool.plugin.mutate.backend.report.utility : toSections;
import dextool.plugin.mutate.backend.type : Mutation, Offset, SourceLoc;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel, ReportSection;
import dextool.type : AbsolutePath, Path, DirName;

import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl;

version (unittest) {
    import unit_threaded : shouldEqual;
}

struct FileIndex {
    Path path;
    string display;

    long aliveMutants;
    long killedMutants;
    long totalMutants;
    // Nr of mutants that are alive but tagged with nomut.
    long aliveNoMut;
}

@safe final class ReportHtml : FileReport, FilesReporter {
    import std.array : Appender;
    import std.stdio : File, writefln, writeln;
    import std.xml : encode;
    import dextool.set;

    const Mutation.Kind[] kinds;
    const ConfigReport conf;

    /// The base directory of logdirs
    const AbsolutePath logDir;
    /// Reports for each file
    const AbsolutePath logFilesDir;

    /// What the user configured.
    MutationKind[] humanReadableKinds;
    Set!ReportSection sections;

    FilesysIO fio;

    // all files that have been produced.
    Appender!(FileIndex[]) files;

    // the context for the file that is currently being processed.
    FileCtx ctx;

    // Report alive mutants in this section
    Diff diff;

    this(const(Mutation.Kind)[] kinds, const ConfigReport conf, FilesysIO fio, ref Diff diff) {
        import std.path : buildPath;

        this.kinds = kinds;
        this.fio = fio;
        this.conf = conf;
        this.logDir = buildPath(conf.logDir, htmlDir).Path.AbsolutePath;
        this.logFilesDir = buildPath(this.logDir, htmlFileDir).Path.AbsolutePath;
        this.diff = diff;

        sections = (conf.reportSection.length == 0 ? conf.reportLevel.toSections
                : conf.reportSection.dup).setFromList;
    }

    override void mutationKindEvent(const MutationKind[] k) {
        import std.file : mkdirRecurse;

        humanReadableKinds = k.dup;
        mkdirRecurse(this.logDir);
        mkdirRecurse(this.logFilesDir);
    }

    override FileReport getFileReportEvent(ref Database db, const ref FileRow fr) {
        import std.path : buildPath;
        import std.stdio : File;
        import dextool.plugin.mutate.backend.report.html.page_files;
        import dextool.plugin.mutate.backend.report.utility : reportStatistics;

        const original = fr.file.dup.pathToHtml;
        const report = (original ~ htmlExt).Path;

        auto stat = reportStatistics(db, kinds, fr.file);

        files.put(FileIndex(report, fr.file, stat.alive,
                stat.killed + stat.timeout + stat.aliveNoMut, stat.total, stat.aliveNoMut));

        const out_path = buildPath(logFilesDir, report).Path.AbsolutePath;

        ctx = FileCtx.make(original);
        ctx.processFile = fr.file;
        ctx.out_ = File(out_path, "w");
        ctx.span = Spanner(tokenize(fio.getOutputDir, fr.file));

        return this;
    }

    override void fileMutantEvent(const ref FileMutantRow fr) {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

        // TODO unnecessary to create the mutation text here.
        // Move it to endFileEvent. This is inefficient.

        // the mutation text has been found to contain '\0' characters when the
        // mutant span multiple lines. These null characters render badly in
        // the html report.
        static string cleanup(const(char)[] raw) {
            import std.algorithm : filter;
            import std.array : array;
            import std.utf;

            return raw.byChar.filter!(a => a != '\0').array.idup;
        }

        auto fin = fio.makeInput(AbsolutePath(ctx.processFile, DirName(fio.getOutputDir)));
        auto txt = makeMutationText(fin, fr.mutationPoint.offset, fr.mutation.kind, fr.lang);
        ctx.span.put(FileMutant(fr.id, fr.mutationPoint.offset,
                cleanup(txt.original), cleanup(txt.mutation), fr.mutation));
    }

    override void endFileEvent(ref Database db) @trusted {
        import std.algorithm : max, each, map, min, canFind;
        import std.array : appender;
        import std.conv : to;
        import std.range : repeat;

        static struct MData {
            MutationId id;
            FileMutant.Text txt;
            Mutation mut;
        }

        static string styleHover(MutationId this_mut, const(FileMutant) m) {
            if (this_mut == m.id)
                return format(`<b class="%s">%s</b>`, pickColor(m).toHover, m.mut.kind);
            return format(`<span class="%s">%s</span>`, pickColor(m).toHover, m.mut.kind);
        }

        Set!MutationId ids;
        auto muts = appender!(MData[])();
        uint line = 1;
        uint column = 1;

        auto root = ctx.doc.mainBody;
        root.addChild("span", "1:").addClass("line_nr");
        foreach (const s; ctx.span.toRange) {
            if (s.tok.loc.line > line)
                column = 1;

            auto meta = MetaSpan(s.muts);

            foreach (const i; 0 .. max(0, s.tok.loc.line - line)) {
                root.addChild("br");
                root.addChild("span", format("%s:", line + i + 1)).addClass("line_nr");
            }
            const spaces = max(0, s.tok.loc.column - column);
            root.addChild(new RawSource(ctx.doc, format("%-(%s%)", "&nbsp;".repeat(spaces))));

            auto d0 = root.addChild("div").setAttribute("style", "display: inline;");
            with (d0.addChild("span", s.tok.spelling)) {
                addClass("original");
                addClass(s.tok.toName);
                if (auto v = meta.status.toVisible)
                    addClass(v);
                if (s.muts.length != 0)
                    addClass(format("%(mutid%s %)", s.muts.map!(a => a.id)));
                if (meta.onClick2.length != 0)
                    setAttribute("onclick", meta.onClick2);
            }

            foreach (m; s.muts) {
                if (!ids.contains(m.id)) {
                    ids.add(m.id);
                    muts.put(MData(m.id, m.txt, m.mut));
                    const inside_fly = format(`%-(%s %)`, s.muts.map!(a => styleHover(m.id, a)))
                        .toJson;
                    const fly = format(`fly(event, %s)`, inside_fly);
                    with (d0.addChild("span", m.mutation)) {
                        addClass("mutant");
                        addClass(s.tok.toName);
                        setAttribute("id", m.id.to!string);
                        setAttribute("onmouseenter", fly);
                        setAttribute("onmouseleave", fly);
                    }
                    d0.addChild("a").setAttribute("href", "#" ~ m.id.to!string);
                }
            }

            line = s.tok.locEnd.line;
            column = s.tok.locEnd.column;
        }

        with (root.addChild("script")) {
            import dextool.plugin.mutate.backend.report.utility : window;

            addChild(new RawSource(ctx.doc, format("var g_mutids = [%(%s,%)];",
                    muts.data.map!(a => a.id))));
            addChild(new RawSource(ctx.doc, format("var g_muts_orgs = [%(%s,%)];",
                    muts.data.map!(a => window(a.txt.original)))));
            addChild(new RawSource(ctx.doc, format("var g_muts_muts = [%(%s,%)];",
                    muts.data.map!(a => window(a.txt.mutation)))));
            addChild(new RawSource(ctx.doc, format("var g_muts_st = [%(%s,%)];",
                    muts.data.map!(a => a.mut.status.to!string))));
        }

        try {
            ctx.out_.write(ctx.doc.toString);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            logger.error("Unable to generate a HTML report for ", ctx.processFile).collectException;
        }
    }

    override void postProcessEvent(ref Database db) @trusted {
        import std.datetime : Clock;
        import std.path : buildPath, baseName;
        import dextool.plugin.mutate.backend.report.html.page_long_term_view;
        import dextool.plugin.mutate.backend.report.html.page_short_term_view;
        import dextool.plugin.mutate.backend.report.html.page_stats;
        import dextool.plugin.mutate.backend.report.html.page_test_groups;

        const stats_f = buildPath(logDir, "stats" ~ htmlExt);
        const short_f = buildPath(logDir, "short_term_view" ~ htmlExt);
        const long_f = buildPath(logDir, "long_term_view" ~ htmlExt);
        const test_groups_f = buildPath(logDir, "test_groups" ~ htmlExt);

        auto index = tmplBasicPage;
        index.title = format("Mutation Testing Report %(%s %) %s",
                humanReadableKinds, Clock.currTime);
        index.mainBody.addChild("p").addChild("a", "Statistics").href = stats_f.baseName;

        if (!diff.empty) {
            index.mainBody.addChild("p").addChild("a", "Short Term View").href = short_f.baseName;
            File(short_f, "w").write(makeShortTermView(db, conf,
                    humanReadableKinds, kinds, diff, fio.getOutputDir));
        }
        index.mainBody.addChild("p").addChild("a", "Long Term View").href = long_f.baseName;
        index.mainBody.addChild("p").addChild("a", "Test Groups").href = test_groups_f.baseName;

        files.data.toIndex(index.mainBody, htmlFileDir);

        File(stats_f, "w").write(makeStats(db, conf, humanReadableKinds, kinds));
        File(long_f, "w").write(makeLongTermView(db, conf, humanReadableKinds, kinds));
        File(test_groups_f, "w").write(makeTestGroups(db, conf, humanReadableKinds, kinds));
        File(buildPath(logDir, "index" ~ htmlExt), "w").write(index.toPrettyString);
    }

    override void endEvent(ref Database) {
    }
}

@safe:
private:

string toJson(string s) {
    import std.json : JSONValue;

    return JSONValue(s).toString;
}

struct FileCtx {
    import std.stdio;

    Path processFile;
    File out_;

    Spanner span;

    Document doc;

    static FileCtx make(string title) @trusted {
        import dextool.plugin.mutate.backend.report.html.js;
        import dextool.plugin.mutate.backend.report.html.tmpl;

        auto r = FileCtx.init;
        r.doc = tmplBasicPage;
        r.doc.title = title;
        r.doc.mainBody.setAttribute("onload", "javascript:init();");

        auto s = r.doc.root.childElements("head")[0].addChild("style");
        s.addChild(new RawSource(r.doc, tmplIndexStyle));

        s = r.doc.root.childElements("head")[0].addChild("script");
        s.addChild(new RawSource(r.doc, js_file));

        r.doc.mainBody.appendHtml(tmplIndexBody);

        return r;
    }
}

/**
 *
 * The source can contain invalid UTF-8 chars therefor every token has to be
 * validated. Otherwise it isn't possible to generate a report.
 */
struct Token {
    import clang.c.Index : CXTokenKind;

    CXTokenKind kind;
    Offset offset;
    SourceLoc loc;
    SourceLoc locEnd;
    string spelling;

    this(CXTokenKind kind, Offset offset, SourceLoc loc, SourceLoc locEnd, string spelling) {
        this.kind = kind;
        this.offset = offset;
        this.loc = loc;
        this.locEnd = locEnd;

        try {
            import std.utf : validate;

            validate(spelling);
            this.spelling = spelling;
        } catch (Exception e) {
            this.spelling = "[invalid utf8]";
        }
    }

    string toId() @safe const {
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
    Mutation mut;

    this(MutationId id, Offset offset, string original, string mutation, Mutation mut) {
        this.id = id;
        this.offset = offset;
        this.txt.original = original;
        this.txt.mutation = mutation;
        this.mut = mut;
    }

    this(MutationId id, Offset offset, string original) {
        this(id, offset, original, null, Mutation.init);
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
        import std.range : zip, StoppingPolicy;
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

void toIndex(FileIndex[] files, Element root, string htmlFileDir) @trusted {
    import std.algorithm : sort;
    import std.conv : to;
    import std.path : buildPath;

    auto tbl = tmplDefaultTable(root, ["Path", "Score", "Alive", "NoMut", "Total"]);

    bool has_suppressed;
    foreach (f; files.sort!((a, b) => a.path < b.path)) {
        auto r = tbl.addChild("tr");
        r.addChild("td").addChild("a", f.display).href = buildPath(htmlFileDir, f.path);

        const score = () {
            if (f.totalMutants == 0)
                return 1.0;
            return cast(double) f.killedMutants / cast(double) f.totalMutants;
        }();
        const style = () {
            if (f.killedMutants == f.totalMutants)
                return "background-color: green";
            if (score < 0.3)
                return "background-color: red";
            if (score < 0.5)
                return "background-color: salmon";
            if (score < 0.8)
                return "background-color: lightyellow";
            if (score < 1.0)
                return "background-color: lightgreen";
            return null;
        }();

        r.addChild("td", format("%.3s", score)).style = style;
        r.addChild("td", f.aliveMutants.to!string).style = style;
        r.addChild("td", f.aliveNoMut.to!string).style = style;
        r.addChild("td", f.totalMutants.to!string).style = style;

        has_suppressed = has_suppressed || f.aliveNoMut != 0;
    }

    root.addChild("p", "NoMut is the number of alive mutants in the file that are ignored.")
        .appendText(" This increases the score.");
}

/// Metadata about the span to be used to e.g. color it.
struct MetaSpan {
    // ordered in priority
    enum StatusColor {
        alive,
        killed,
        timeout,
        killedByCompiler,
        unknown,
        none,
    }

    StatusColor status;
    string onClick;
    string onClick2;

    this(const(FileMutant)[] muts) {
        immutable click_fmt = "onclick='ui_set_mut(%s)'";
        immutable click_fmt2 = "ui_set_mut(%s)";
        status = StatusColor.none;

        foreach (ref const m; muts) {
            status = pickColor(m, status);
            if (onClick.length == 0 && m.mut.status == Mutation.Status.alive) {
                onClick = format(click_fmt, m.id);
                onClick2 = format(click_fmt2, m.id);
            }
        }

        if (onClick.length == 0 && muts.length != 0) {
            onClick = format(click_fmt, muts[0].id);
            onClick2 = format(click_fmt2, muts[0].id);
        }
    }
}

MetaSpan.StatusColor pickColor(const FileMutant m,
        MetaSpan.StatusColor status = MetaSpan.StatusColor.none) {
    final switch (m.mut.status) {
    case Mutation.Status.alive:
        status = MetaSpan.StatusColor.alive;
        break;
    case Mutation.Status.killed:
        if (status > MetaSpan.StatusColor.killed)
            status = MetaSpan.StatusColor.killed;
        break;
    case Mutation.Status.killedByCompiler:
        if (status > MetaSpan.StatusColor.killedByCompiler)
            status = MetaSpan.StatusColor.killedByCompiler;
        break;
    case Mutation.Status.timeout:
        if (status > MetaSpan.StatusColor.timeout)
            status = MetaSpan.StatusColor.timeout;
        break;
    case Mutation.Status.unknown:
        if (status > MetaSpan.StatusColor.unknown)
            status = MetaSpan.StatusColor.unknown;
        break;
    }
    return status;
}

string toVisible(MetaSpan.StatusColor s) {
    if (s == MetaSpan.StatusColor.none)
        return null;
    return format("status_%s", s);
}

string toHover(MetaSpan.StatusColor s) {
    if (s == MetaSpan.StatusColor.none)
        return null;
    return format("hover_%s", s);
}
