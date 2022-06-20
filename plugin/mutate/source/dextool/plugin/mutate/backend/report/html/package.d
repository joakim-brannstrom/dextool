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
import std.algorithm : max, each, map, min, canFind, sort, filter, joiner;
import std.array : Appender, appender, array, empty;
import std.datetime : dur;
import std.exception : collectException;
import std.format : format;
import std.functional : toDelegate;
import std.path : buildPath, baseName, relativePath;
import std.range : only;
import std.stdio : File;
import std.typecons : tuple, Tuple;
import std.utf : toUTF8, byChar;

import arsd.dom : Document, Element, require, Table, RawSource, Link;
import my.actor;
import my.actor.utility.limiter;
import my.gc.refc;
import my.optional;
import my.set;

import dextool.plugin.mutate.backend.database : Database, FileRow, FileMutantRow, MutationId;
import dextool.plugin.mutate.backend.database.type : CovRegionStatus;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : FileReport, FilesReporter;
import dextool.plugin.mutate.backend.type : Mutation, Offset, SourceLoc, Token;
import dextool.plugin.mutate.backend.utility : Profile;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportSection;
import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.report.html.constants : HtmlStyle = Html, DashboardCss;
import dextool.plugin.mutate.backend.report.html.tmpl;
import dextool.plugin.mutate.backend.resource;

@safe:

void report(ref System sys, AbsolutePath dbPath, const MutationKind[] userKinds,
        ConfigReport conf, FilesysIO fio, ref Diff diff) @trusted {
    import dextool.plugin.mutate.backend.database : FileMutantRow;
    import dextool.plugin.mutate.backend.mutation_type : toInternal;

    auto flowCtrl = sys.spawn(&spawnFlowControlTotalCPUs);
    auto reportCollector = sys.spawn(&spawnFileReportCollector, flowCtrl);
    auto overview = sys.spawn(&spawnOverviewActor, flowCtrl, reportCollector,
            dbPath, userKinds.dup, conf, fio, diff);

    auto self = scopedActor;
    self.request(overview, infTimeout).send(WaitForDoneMsg.init).then((bool a) {});
}

struct FileIndex {
    import dextool.plugin.mutate.backend.report.analyzers : MutationScore;

    Path path;
    string display;
    MutationScore stat;
}

@safe:
private:

string toJson(string s) {
    import std.json : JSONValue;

    return JSONValue(s).toString;
}

struct FileCtx {
    import std.stdio : File;
    import blob_model : Blob;
    import dextool.plugin.mutate.backend.database : FileId, TestCaseInfo2;

    Path processFile;
    File out_;

    Spanner span;

    Document doc;

    // The text of the current file that is being processed.
    Blob raw;

    /// Database ID for this file.
    FileId fileId;

    /// Find the test cases that killed a mutant. They are sorted by most killed -> least killed.
    TestCaseInfo[][MutationId] tcKilledMutant;

    /// All test cases in the file.
    TestCaseInfo[] testCases;

    static FileCtx make(string title, FileId id, Blob raw, TestCaseInfo2[] tc_info) @trusted {
        import dextool.plugin.mutate.backend.report.html.tmpl;

        auto r = FileCtx.init;
        r.doc = tmplBasicPage.filesCss;
        r.doc.title = title;
        r.doc.mainBody.setAttribute("onload", "javascript:init();");

        auto s = r.doc.root.childElements("head")[0].addChild("style");
        s.addChild(new RawSource(r.doc, tmplIndexStyle));

        s = r.doc.root.childElements("head")[0].addChild("script");
        s.addChild(new RawSource(r.doc, jsSource));

        r.doc.mainBody.appendHtml(tmplIndexBody);

        r.fileId = id;

        r.raw = raw;

        typeof(tcKilledMutant) tmp;
        foreach (a; tc_info) {
            foreach (mut; a.killed) {
                tmp.update(mut, { return [TestCaseInfo(a.name, a.killed.length)]; },
                        (ref TestCaseInfo[] v) => v ~= TestCaseInfo(a.name, a.killed.length));
            }
        }
        r.testCases = tc_info.map!(a => TestCaseInfo(a.name, a.killed.length)).array;

        foreach (kv; tmp.byKeyValue) {
            r.tcKilledMutant[kv.key] = kv.value.sort.array;
        }

        return r;
    }

    TestCaseInfo[] getTestCaseInfo(MutationId mutationId) @safe pure nothrow {
        if (auto v = mutationId in tcKilledMutant)
            return *v;
        return null;
    }

    static struct TestCaseInfo {
        import dextool.plugin.mutate.backend.type : TestCase;

        TestCase name;
        long killed;

        int opCmp(ref const typeof(this) s) @safe pure nothrow const @nogc scope {
            if (killed < s.killed)
                return -1;
            else if (killed > s.killed)
                return 1;
            else if (name < s.name)
                return -1;
            else if (name > s.name)
                return 1;
            return 0;
        }

        bool opEquals(ref const typeof(this) s) @safe pure nothrow const @nogc scope {
            return name == s.name;
        }

        size_t toHash() @safe nothrow const {
            return name.toHash;
        }
    }
}

auto tokenize(AbsolutePath base_dir, Path f) @trusted {
    import std.typecons : Yes;
    import libclang_ast.context;
    static import dextool.plugin.mutate.backend.utility;

    const fpath = buildPath(base_dir, f).Path.AbsolutePath;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    return dextool.plugin.mutate.backend.utility.tokenize!(Yes.splitMultiLineTokens)(ctx, fpath);
}

struct FileMutant {
nothrow:
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
        import std.utf : validate;
        import dextool.plugin.mutate.backend.type : invalidUtf8;

        this.id = id;
        this.offset = offset;
        this.mut = mut;

        try {
            validate(original);
            this.txt.original = original;
        } catch (Exception e) {
            this.txt.original = invalidUtf8;
        }

        try {
            validate(mutation);
            // users prefer being able to see what has been removed.
            if (mutation.length == 0)
                this.txt.mutation = "/* " ~ this.txt.original ~ " */";
            else
                this.txt.mutation = mutation;
        } catch (Exception e) {
            this.txt.mutation = invalidUtf8;
        }
    }

    this(MutationId id, Offset offset, string original) {
        this(id, offset, original, null, Mutation.init);
    }

    string original() @safe pure nothrow const @nogc {
        return txt.original;
    }

    string mutation() @safe pure nothrow const @nogc {
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

    void put(const FileMutant fm) @trusted {
        muts.insert(fm);
    }

    SpannerRange toRange() @safe {
        return SpannerRange(tokens, muts);
    }

    string toString() @safe pure const {
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
    import std.conv;
    import std.range;
    import clang.c.Index : CXTokenKind;

    import unit_threaded : shouldEqual;

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
    res[1].muts[0].id.get.shouldEqual(2);
    res[2].muts.length.shouldEqual(0);
    res[3].muts[0].id.get.shouldEqual(3);
    res[4].muts[0].id.get.shouldEqual(3);
    res[5].muts[0].id.get.shouldEqual(4);
    res[6].muts[0].id.get.shouldEqual(4);
    res[7].muts[0].id.get.shouldEqual(4);
    res[8].muts.length.shouldEqual(0);
    res[9].muts.length.shouldEqual(2);
    res[9].muts[0].id.get.shouldEqual(5);
    res[9].muts[1].id.get.shouldEqual(6);
    res[10].muts[0].id.get.shouldEqual(6);
    res[11].muts.length.shouldEqual(0);
    res[12].muts[0].id.get.shouldEqual(1);
    res[13].muts.length.shouldEqual(0);
}

void toIndex(FileIndex[] files, Element root, string htmlFileDir) @trusted {
    import std.algorithm : sort, filter;
    import std.conv : to;

    DashboardCss.h2(root.addChild(new Link("#files", null)).setAttribute("id", "files"), "Files");

    auto fltr = root.addChild("div").addClass("input-group");
    fltr.addChild("input").setAttribute("type", "search").setAttribute("id", "fileFilterInput").setAttribute("onkeyup",
            "filter_table_on_search('fileFilterInput', 'fileTable')").addClass(
            "form-control").setAttribute("placeholder", "Search...");

    auto tbl = tmplSortableTable(root, [
            "Path", "Score", "Alive", "NoMut", "Total", "Time (min)"
            ]);
    tbl.setAttribute("id", "fileTable");

    // Users are not interested that files that contains zero mutants are shown
    // in the list. It is especially annoying when they are marked with dark
    // green.
    bool hasSuppressed;
    auto noMutants = appender!(FileIndex[])();
    foreach (f; files.sort!((a, b) => a.path < b.path)) {
        if (f.stat.total == 0) {
            noMutants.put(f);
        } else {
            auto r = tbl.appendRow();
            r.addChild("td").addChild("a", f.display).href = buildPath(htmlFileDir, f.path);

            const score = f.stat.score;
            const style = () {
                if (f.stat.total == 0)
                    return "background-color: lightgrey";
                if (f.stat.killed == f.stat.total)
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

            r.addChild("td", format!"%.3s"(score)).style = style;
            r.addChild("td", f.stat.alive.to!string);
            r.addChild("td", f.stat.aliveNoMut.to!string);
            r.addChild("td", f.stat.total.to!string);
            r.addChild("td", f.stat
                    .totalTime
                    .sum
                    .total!"minutes"
                    .to!string);

            hasSuppressed = hasSuppressed || f.stat.aliveNoMut != 0;
        }
    }

    if (!noMutants.data.empty) {
        root.addChild("p", "Analyzed files with no mutants in them.");
        auto noMutTbl = tmplSortableTable(root, ["Path"]);
        foreach (f; noMutants.data) {
            auto r = noMutTbl.appendRow();
            r.addChild("td").addChild("a", f.display).href = buildPath(htmlFileDir, f.path);
        }
    }

    if (hasSuppressed) {
        root.addChild("p", "NoMut is the number of alive mutants in the file that are ignored.")
            .appendText(" This increases the score.");
    }
}

/** Metadata about the span to be used to e.g. color it.
 *
 * Each span has a mutant that becomes activated when the user click on the
 * span. The user most likely is interested in seeing **a** mutant that has
 * survived on that point becomes the color is red.
 *
 * This is why the algorithm uses the same prio as the one for choosing
 * color. These two are strongly correlated with each other.
 */
struct MetaSpan {
    // ordered in priority
    enum StatusColor {
        alive,
        killed,
        timeout,
        memOverload,
        killedByCompiler,
        skipped,
        unknown,
        none,
        noCoverage,
    }

    StatusColor status;
    string onClick;

    this(const(FileMutant)[] muts) {
        immutable click_fmt2 = "ui_set_mut(%s)";
        status = StatusColor.none;

        foreach (ref const m; muts) {
            status = pickColor(m, status);
            if (onClick.length == 0 && m.mut.status == Mutation.Status.alive) {
                onClick = format(click_fmt2, m.id.get);
            }
        }

        if (onClick.length == 0 && muts.length != 0) {
            onClick = format(click_fmt2, muts[0].id.get);
        }
    }
}

/// Choose a color for a mutant span by prioritizing alive mutants above all.
MetaSpan.StatusColor pickColor(const FileMutant m,
        MetaSpan.StatusColor status = MetaSpan.StatusColor.none) {
    final switch (m.mut.status) {
    case Mutation.Status.noCoverage:
        status = MetaSpan.StatusColor.noCoverage;
        break;
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
    case Mutation.Status.memOverload:
        if (status > MetaSpan.StatusColor.memOverload)
            status = MetaSpan.StatusColor.memOverload;
        break;
    case Mutation.Status.skipped:
        if (status > MetaSpan.StatusColor.skipped)
            status = MetaSpan.StatusColor.skipped;
        break;
    case Mutation.Status.unknown:
        if (status > MetaSpan.StatusColor.unknown)
            status = MetaSpan.StatusColor.unknown;
        break;
    case Mutation.Status.equivalent:
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

/// DB data for coverage-visualization

bool[uint] extractLineCovData(CovRegionStatus[] dbData, ref FileCtx ctx) {
    bool[uint] lineList;

    static struct T {
        int value;
        bool status;
    }

    T[] regions;

    foreach (region; dbData) {
        bool status = region.status;
        int begin = region.region.begin;
        int end = region.region.end;

        T temp;
        temp.value = begin;
        temp.status = status;
        regions ~= temp;
        temp.value = end;
        regions ~= temp;
    }

    bool inRegion = false;
    bool currentStatus = false;
    int byteCounter = 0;
    int lineCounter = 1;

    foreach (b; ctx.raw.content) {
        if (b == '\n') {
            lineCounter++;
        }
        if (!regions.empty && byteCounter == regions[0].value) {
            currentStatus = regions[0].status;
            inRegion = !inRegion;
            regions = regions[1 .. regions.length];
        }
        if (inRegion) {
            lineList[lineCounter] = currentStatus;
        }
        byteCounter++;
    }
    return lineList;
}


void generateFile(ref Database db, ref FileCtx ctx) @trusted {
    import std.conv : to;
    import std.range : repeat, enumerate;
    import std.traits : EnumMembers;
    import dextool.plugin.mutate.type : MutationKind;
    import dextool.plugin.mutate.backend.database.type : MutantMetaData;
    import dextool.plugin.mutate.backend.report.utility : window;
    import dextool.plugin.mutate.backend.mutation_type : toUser;

    static struct MData {
        MutationId id;
        FileMutant.Text txt;
        Mutation mut;
        MutantMetaData metaData;
    }

    auto root = ctx.doc.mainBody;
    auto lines = root.addChild("table").setAttribute("id", "locs").setAttribute("cellpadding", "0");
    auto line = lines.addChild("tr").addChild("td").setAttribute("id", "loc-1");
    line.addClass("loc");

    line.addChild("span", "1:").addClass("line_nr");
    auto mut_data = appender!(string[])();
    mut_data.put("var g_muts_data = {};");
    mut_data.put("g_muts_data[-1] = {'kind' : null, 'status' : null, 'testCases' : null, 'orgText' : null, 'mutText' : null, 'meta' : null};");

    // used to make sure that metadata about a mutant is only written onces
    // to the global arrays.
    Set!MutationId metadataOnlyOnce;
    auto muts = appender!(MData[])();

    // this is the last location. It is used to calculate the num of
    // newlines, detect when a line changes etc.
    auto lastLoc = SourceLoc(1, 1);

    // read coverage data and save covered lines in lineList
    auto dbData = db.coverageApi.getCoverageStatus(ctx.fileId);

    auto lineList = extractLineCovData(dbData, ctx);

    foreach (const s; ctx.span.toRange) {
        if (s.tok.loc.line > lastLoc.line) {
            lastLoc.column = 1;
        }
        auto meta = MetaSpan(s.muts);

        foreach (const i; 0 .. max(0, s.tok.loc.line - lastLoc.line)) {
            line = lines.addChild("tr").addChild("td");
            line.setAttribute("id", format("%s-%s", "loc", lastLoc.line + i + 1))
                .addClass("loc").addChild("span", format("%s:",
                        lastLoc.line + i + 1)).addClass("line_nr");

            if (auto v = (lastLoc.line + i + 1) in lineList) {
                if (*v)
                    line.addClass("loc_covered");
                else
                    line.addClass("loc_noncovered");
            }

            // force a newline in the generated html to improve readability
            lines.appendText("\n");
        }

        const spaces = max(0, s.tok.loc.column - lastLoc.column);
        line.addChild(new RawSource(ctx.doc, format("%-(%s%)", "&nbsp;".repeat(spaces))));

        auto d0 = line.addChild("div").setAttribute("style", "display: inline;");
        with (d0.addChild("span", s.tok.spelling)) {
            addClass("original");
            addClass(s.tok.toName);
            if (auto v = meta.status.toVisible)
                addClass(v);
            if (s.muts.length != 0) {
                addClass(format("%(mutid%s %)", s.muts.map!(a => a.id)));
                line.removeClass("loc_covered");
                line.removeClass("loc_noncovered");
            }
            if (meta.onClick.length != 0)
                setAttribute("onclick", meta.onClick);
        }

        foreach (m; s.muts.filter!(m => m.id !in metadataOnlyOnce)) {
            metadataOnlyOnce.add(m.id);

            const metadata = db.mutantApi.getMutantationMetaData(m.id);

            muts.put(MData(m.id, m.txt, m.mut, metadata));
            {
                auto mutantHtmlTag = d0.addChild("span").addClass("mutant")
                    .setAttribute("id", m.id.toString);
                if (m.mutation.canFind('\n')) {
                    mutantHtmlTag.addChild("pre", m.mutation).addClass("mutant2");
                } else {
                    mutantHtmlTag.appendText(m.mutation);
                }
            }

            auto testCases = ctx.getTestCaseInfo(m.id);
            if (testCases.empty) {
                mut_data.put(format("g_muts_data[%s] = {'kind' : %s, 'kindGroup' : %s, 'status' : %s, 'testCases' : null, 'orgText' : %s, 'mutText' : %s, 'meta' : '%s'};",
                        m.id, m.mut.kind.to!int, toUser(m.mut.kind).to!int,
                        m.mut.status.to!ubyte, toJson(window(m.txt.original)),
                        toJson(window(m.txt.mutation)), metadata.kindToString));
            } else {
                mut_data.put(format("g_muts_data[%s] = {'kind' : %s, 'kindGroup' : %s, 'status' : %s, 'testCases' : [%('%s',%)'], 'orgText' : %s, 'mutText' : %s, 'meta' : '%s'};",
                        m.id, m.mut.kind.to!int, toUser(m.mut.kind).to!int,
                        m.mut.status.to!ubyte, testCases.map!(a => a.name),
                        toJson(window(m.txt.original)),
                        toJson(window(m.txt.mutation)), metadata.kindToString));
            }
        }
        lastLoc = s.tok.locEnd;
    }

    // make sure there is a newline before the script start to improve
    // readability of the html document source.
    root.appendText("\n");

    with (root.addChild("script")) {
        // force a newline in the generated html to improve readability
        appendText("\n");
        addChild(new RawSource(ctx.doc, format("const MAX_NUM_TESTCASES = %s;",
                db.testCaseApi.getDetectedTestCases.length)));
        appendText("\n");
        addChild(new RawSource(ctx.doc, format("const g_mutids = [%(%s,%)];",
                muts.data.map!(a => a.id))));
        appendText("\n");
        addChild(new RawSource(ctx.doc, format("const g_mut_st_map = [%('%s',%)'];",
                [EnumMembers!(Mutation.Status)])));
        appendText("\n");
        addChild(new RawSource(ctx.doc, format("const g_mut_kind_map = [%('%s',%)'];",
                [EnumMembers!(Mutation.Kind)])));
        appendText("\n");
        addChild(new RawSource(ctx.doc, format("const g_mut_kindGroup_map = [%('%s',%)'];",
                [EnumMembers!(MutationKind)])));
        appendText("\n");

        // Creates a list of number of kills per testcase.
        appendChild(new RawSource(ctx.doc, "var g_testcases_kills = {}"));
        appendText("\n");
        foreach (tc; ctx.testCases) {
            appendChild(new RawSource(ctx.doc,
                    format("g_testcases_kills['%s'] = [%s];", tc.name, tc.killed)));
            appendText("\n");
        }
        appendChild(new RawSource(ctx.doc, mut_data.data.joiner("\n").toUTF8));
        appendText("\n");
    }

    try {
        ctx.out_.write(ctx.doc.toString);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        logger.error("Unable to generate a HTML report for ", ctx.processFile).collectException;
    }
}

Document makeDashboard() @trusted {
    import dextool.plugin.mutate.backend.resource : dashboard, jsIndex;

    auto data = dashboard();

    auto doc = new Document(data.dashboardHtml.get);
    auto style = doc.root.childElements("head")[0].addChild("style");
    style.addChild(new RawSource(doc, data.bootstrapCss.get));
    style.addChild(new RawSource(doc, data.dashboardCss.get));
    style.addChild(new RawSource(doc, tmplDefaultCss));

    auto script = doc.root.childElements("head")[0].addChild("script");
    script.addChild(new RawSource(doc, data.jquery.get));
    script.addChild(new RawSource(doc, data.bootstrapJs.get));
    script.addChild(new RawSource(doc, data.moment.get));
    script.addChild(new RawSource(doc, data.chart.get));
    script.addChild(new RawSource(doc, jsIndex));

    // jsIndex provide init()
    doc.mainBody.setAttribute("onload", "init()");

    return doc;
}

struct NavbarItem {
    string name;
    string link;
}

void addNavbarItems(NavbarItem[] items, Element root) @trusted {
    foreach (item; items) {
        root.addChild("li").addChild(new Link(item.link, item.name));
    }
}

struct InitMsg {
}

struct DoneMsg {
}

struct GenerateReportMsg {
}

struct FailMsg {
}

alias FileReportActor = typedActor!(void function(InitMsg, AbsolutePath dbPath, AbsolutePath logFilesDir),
        void function(AbsolutePath logFilesDir), void function(GenerateReportMsg),
        void function(DoneMsg), void function(FailMsg));

auto spawnFileReport(FileReportActor.Impl self, FlowControlActor.Address flowCtrl,
        FileReportCollectorActor.Address collector,
        AbsolutePath dbPath, FilesysIO fio, Mutation.Kind[] kinds,
        ConfigReport conf, AbsolutePath logFilesDir, FileRow fr) @trusted {
    static struct State {
        Mutation.Kind[] kinds;
        ConfigReport conf;
        FlowControlActor.Address flowCtrl;
        FileReportCollectorActor.Address collector;
        FileRow fileRow;

        Path reportFile;

        Database db;

        FileCtx ctx;
    }

    auto st = tuple!("self", "state", "fio")(self, refCounted(State(kinds,
            conf, flowCtrl, collector, fr)), fio.dup);
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, InitMsg, AbsolutePath dbPath, AbsolutePath logFilesDir) @trusted {
        ctx.state.get.db = Database.make(dbPath);
        send(ctx.self, logFilesDir);
    }

    static void start(ref Ctx ctx, AbsolutePath logFilesDir) @safe nothrow {
        import dextool.plugin.mutate.backend.report.html.utility : pathToHtml;

        try {
            const original = ctx.state.get.fileRow.file.idup.pathToHtml;
            const report = (original ~ HtmlStyle.ext).Path;
            ctx.state.get.reportFile = report;

            const out_path = buildPath(logFilesDir, report).Path.AbsolutePath;

            auto raw = ctx.fio.makeInput(AbsolutePath(buildPath(ctx.fio.getOutputDir,
                    ctx.state.get.fileRow.file)));

            auto tc_info = ctx.state.get.db.testCaseApi.getAllTestCaseInfo2(
                    ctx.state.get.fileRow.id, ctx.state.get.kinds);

            ctx.state.get.ctx = FileCtx.make(original, ctx.state.get.fileRow.id, raw, tc_info);
            ctx.state.get.ctx.processFile = ctx.state.get.fileRow.file;
            ctx.state.get.ctx.out_ = File(out_path, "w");
            ctx.state.get.ctx.span = Spanner(tokenize(ctx.fio.getOutputDir,
                    ctx.state.get.fileRow.file));

            send(ctx.self, GenerateReportMsg.init);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            send(ctx.self, FailMsg.init).collectException;
        }
    }

    static void run(ref Ctx ctx, GenerateReportMsg) @safe nothrow {
        auto profile = Profile("html file report " ~ ctx.state.get.fileRow.file);
        void fn(const ref FileMutantRow fr) {
            import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

            // TODO unnecessary to create the mutation text here.
            // Move it to endFileEvent. This is inefficient.

            // the mutation text has been found to contain '\0' characters when the
            // mutant span multiple lines. These null characters render badly in
            // the html report.
            static string cleanup(const(char)[] raw) @safe nothrow {
                return raw.byChar.filter!(a => a != '\0').array.idup;
            }

            auto txt = makeMutationText(ctx.state.get.ctx.raw,
                    fr.mutationPoint.offset, fr.mutation.kind, fr.lang);
            ctx.state.get.ctx.span.put(FileMutant(fr.id,
                    fr.mutationPoint.offset, cleanup(txt.original),
                    cleanup(txt.mutation), fr.mutation));
        }

        try {
            ctx.state.get.db.iterateFileMutants(ctx.state.get.kinds,
                    ctx.state.get.fileRow.file, &fn);
            generateFile(ctx.state.get.db, ctx.state.get.ctx);

            send(ctx.self, DoneMsg.init);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            send(ctx.self, FailMsg.init).collectException;
        }
    }

    static void done(ref Ctx ctx, DoneMsg) @safe nothrow {
        import dextool.plugin.mutate.backend.report.analyzers : reportScore;

        try {
            auto stat = reportScore(ctx.state.get.db, ctx.state.get.kinds,
                    ctx.state.get.fileRow.file);
            send(ctx.state.get.collector, FileIndex(ctx.state.get.reportFile,
                    ctx.state.get.fileRow.file, stat));

            ctx.self.shutdown;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            send(ctx.self, FailMsg.init).collectException;
        }
    }

    static void failed(ref Ctx ctx, FailMsg) @safe {
        import dextool.plugin.mutate.backend.report.analyzers : MutationScore;

        logger.warning("Failed to generate a HTML report for ", ctx.state.get.fileRow.file);
        send(ctx.state.get.collector, FileIndex(ctx.state.get.reportFile,
                ctx.state.get.fileRow.file, MutationScore.init));
        ctx.self.shutdown;
    }

    self.exceptionHandler = toDelegate(&logExceptionHandler);

    self.request(flowCtrl, infTimeout).send(TakeTokenMsg.init)
        .capture(self.address, dbPath, logFilesDir).then((ref Tuple!(FileReportActor.Address,
                AbsolutePath, AbsolutePath) ctx, my.actor.utility.limiter.Token _) => send(ctx[0],
                InitMsg.init, ctx[1], ctx[2]));

    return impl(self, &init_, capture(st), &start, capture(st), &done,
            capture(st), &run, capture(st), &failed, capture(st));
}

struct GetIndexesMsg {
}

struct StartReporterMsg {
}

struct DoneStartingReportersMsg {
}

alias FileReportCollectorActor = typedActor!(void function(StartReporterMsg),
        void function(DoneStartingReportersMsg), /// Collects an index.
        void function(FileIndex), /// Returns all collected indexes.
        FileIndex[]function(GetIndexesMsg));

/// Collect file indexes from finished reports
auto spawnFileReportCollector(FileReportCollectorActor.Impl self, FlowControlActor.Address flow) {
    static struct State {
        FlowControlActor.Address flow;

        uint reporters;
        bool doneStarting;
        FileIndex[] files;
        Promise!(FileIndex[]) promise;

        bool done() {
            return doneStarting && (reporters == files.length);
        }
    }

    auto st = tuple!("self", "state")(self, refCounted(State(flow)));
    alias Ctx = typeof(st);

    static void started(ref Ctx ctx, StartReporterMsg) {
        ctx.state.get.reporters++;
    }

    static void doneStarting(ref Ctx ctx, DoneStartingReportersMsg) {
        ctx.state.get.doneStarting = true;
    }

    static void index(ref Ctx ctx, FileIndex fi) {
        ctx.state.get.files ~= fi;

        send(ctx.state.get.flow, ReturnTokenMsg.init);
        logger.infof("Generated %s (%s)", fi.display, fi.stat.score);

        if (ctx.state.get.done && !ctx.state.get.promise.empty) {
            ctx.state.get.promise.deliver(ctx.state.get.files);
            ctx.self.shutdown;
        }
    }

    static RequestResult!(FileIndex[]) getIndexes(ref Ctx ctx, GetIndexesMsg) {
        if (ctx.state.get.done) {
            if (!ctx.state.get.promise.empty)
                ctx.state.get.promise.deliver(ctx.state.get.files);
            ctx.self.shutdown;
            return typeof(return)(ctx.state.get.files);
        }

        assert(ctx.state.get.promise.empty, "can only be one active request at a time");
        ctx.state.get.promise = makePromise!(FileIndex[]);
        return typeof(return)(ctx.state.get.promise);
    }

    self.exceptionHandler = () @trusted {
        return toDelegate(&logExceptionHandler);
    }();
    return impl(self, &started, capture(st), &doneStarting, capture(st),
            &index, capture(st), &getIndexes, capture(st));
}

struct GetPagesMsg {
}

alias SubPage = Tuple!(string, "fileName", string, "linkTxt");
alias SubContent = Tuple!(string, "name", string, "tag", string, "content");

alias AnalyzeReportCollectorActor = typedActor!(void function(StartReporterMsg), void function(DoneStartingReportersMsg), /// Collects an index.
        void function(SubPage), void function(SubContent), void function(CheckDoneMsg),
        Tuple!(SubPage[], SubContent[]) function(GetPagesMsg));

auto spawnAnalyzeReportCollector(AnalyzeReportCollectorActor.Impl self,
        FlowControlActor.Address flow) {
    alias Result = Tuple!(SubPage[], SubContent[]);
    static struct State {
        FlowControlActor.Address flow;

        uint awaitingReports;
        bool doneStarting;

        SubPage[] subPages;
        SubContent[] subContent;
        Promise!(Tuple!(SubPage[], SubContent[])) promise;

        bool done() {
            return doneStarting && (awaitingReports == (subPages.length + subContent.length));
        }
    }

    auto st = tuple!("self", "state")(self, refCounted(State(flow)));
    alias Ctx = typeof(st);

    static void started(ref Ctx ctx, StartReporterMsg) {
        ctx.state.get.awaitingReports++;
    }

    static void doneStarting(ref Ctx ctx, DoneStartingReportersMsg) {
        ctx.state.get.doneStarting = true;
    }

    static void subPage(ref Ctx ctx, SubPage p) {
        ctx.state.get.subPages ~= p;
        send(ctx.self, CheckDoneMsg.init);
        send(ctx.state.get.flow, ReturnTokenMsg.init);
        logger.infof("Generated %s", p.linkTxt);
    }

    static void subContent(ref Ctx ctx, SubContent p) {
        ctx.state.get.subContent ~= p;
        send(ctx.self, CheckDoneMsg.init);
        send(ctx.state.get.flow, ReturnTokenMsg.init);
        logger.infof("Generated %s", p.name);
    }

    static void checkDone(ref Ctx ctx, CheckDoneMsg) {
        // defensive programming in case a promise request arrive after the last page is generated.
        delayedSend(ctx.self, delay(1.dur!"seconds"), CheckDoneMsg.init);
        if (!ctx.state.get.done)
            return;

        if (!ctx.state.get.promise.empty) {
            ctx.state.get.promise.deliver(tuple(ctx.state.get.subPages, ctx.state.get.subContent));
            ctx.self.shutdown;
        }
    }

    static RequestResult!Result getPages(ref Ctx ctx, GetPagesMsg) {
        if (ctx.state.get.done) {
            if (!ctx.state.get.promise.empty)
                ctx.state.get.promise.deliver(tuple(ctx.state.get.subPages,
                        ctx.state.get.subContent));
            ctx.self.shutdown;
            return typeof(return)(tuple(ctx.state.get.subPages, ctx.state.get.subContent));
        }

        assert(ctx.state.get.promise.empty, "can only be one active request at a time");
        ctx.state.get.promise = makePromise!Result;
        return typeof(return)(ctx.state.get.promise);
    }

    self.exceptionHandler = () @trusted {
        return toDelegate(&logExceptionHandler);
    }();
    return impl(self, &started, capture(st), &doneStarting, capture(st),
            &subPage, capture(st), &checkDone, capture(st), &getPages,
            capture(st), &subContent, capture(st));
}

struct StartAnalyzersMsg {
}

struct WaitForDoneMsg {
}

struct IndexWaitMsg {
}

struct CheckDoneMsg {
}

struct GenerateIndexMsg {
}

alias OverviewActor = typedActor!(void function(InitMsg, AbsolutePath), void function(StartAnalyzersMsg, AbsolutePath),
        void function(StartReporterMsg, AbsolutePath), void function(IndexWaitMsg),
        void function(GenerateIndexMsg), void function(CheckDoneMsg), // Returns a response when the reporting is done.
        bool function(WaitForDoneMsg));

/** Generate `index.html` and act as the top coordinating actor that spawn,
 * control and summarises the result from all the sub-report actors.
 */
auto spawnOverviewActor(OverviewActor.Impl self, FlowControlActor.Address flowCtrl,
        FileReportCollectorActor.Address fileCollector,
        AbsolutePath dbPath, MutationKind[] userKinds, ConfigReport conf,
        FilesysIO fio, ref Diff diff) @trusted {
    import std.stdio : writefln, writeln;
    import undead.xml : encode;
    import dextool.plugin.mutate.backend.report.analyzers : TestCaseMetadata;

    static struct State {
        FlowControlActor.Address flow;
        FileReportCollectorActor.Address fileCollector;
        ConfigReport conf;

        // Report alive mutants in this section
        Diff diff;

        /// What the user configured.
        MutationKind[] humanReadableKinds;

        Set!ReportSection sections;

        Mutation.Kind[] kinds;

        /// The base directory of logdirs
        AbsolutePath logDir;
        /// Reports for each file
        AbsolutePath logFilesDir;
        /// Reports for each test case
        AbsolutePath logTestCasesDir;

        // User provided metadata.
        TestCaseMetadata metaData;

        Database db;

        FileIndex[] files;
        SubPage[] subPages;
        SubContent[] subContent;

        /// signals that the whole report is done.
        bool reportsDone;
        bool filesDone;
        bool done;
        Promise!bool waitForDone;
    }

    auto st = tuple!("self", "state", "fio")(self, refCounted(State(flowCtrl,
            fileCollector, conf, diff, userKinds, conf.reportSection.toSet)), fio.dup);
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, InitMsg, AbsolutePath dbPath) {
        import std.file : mkdirRecurse;
        import dextool.plugin.mutate.backend.mutation_type : toInternal;
        import dextool.plugin.mutate.backend.report.analyzers : parseTestCaseMetadata;

        ctx.state.get.db = Database.make(dbPath);

        ctx.state.get.kinds = toInternal(ctx.state.get.humanReadableKinds);

        ctx.state.get.logDir = buildPath(ctx.state.get.conf.logDir, HtmlStyle.dir)
            .Path.AbsolutePath;
        ctx.state.get.logFilesDir = buildPath(ctx.state.get.logDir,
                HtmlStyle.fileDir).Path.AbsolutePath;
        ctx.state.get.logTestCasesDir = buildPath(ctx.state.get.logDir,
                HtmlStyle.testCaseDir).Path.AbsolutePath;

        if (ctx.state.get.conf.testMetadata.hasValue)
            ctx.state.get.metaData = parseTestCaseMetadata((cast(Optional!(
                    ConfigReport.TestMetaData)) ctx.state.get.conf.testMetadata).orElse(
                    ConfigReport.TestMetaData(AbsolutePath.init)).get);

        foreach (a; only(ctx.state.get.logDir, ctx.state.get.logFilesDir,
                ctx.state.get.logTestCasesDir))
            mkdirRecurse(a);

        send(ctx.self, StartReporterMsg.init, dbPath);
        send(ctx.self, StartAnalyzersMsg.init, dbPath);
    }

    static void startAnalyzers(ref Ctx ctx, StartAnalyzersMsg, AbsolutePath dbPath) {
        import dextool.plugin.mutate.backend.report.html.page_diff;
        import dextool.plugin.mutate.backend.report.html.page_minimal_set;
        import dextool.plugin.mutate.backend.report.html.page_mutant;
        import dextool.plugin.mutate.backend.report.html.page_nomut;
        import dextool.plugin.mutate.backend.report.html.page_stats;
        import dextool.plugin.mutate.backend.report.html.page_test_case;
        import dextool.plugin.mutate.backend.report.html.page_test_group_similarity;
        import dextool.plugin.mutate.backend.report.html.page_test_groups;
        import dextool.plugin.mutate.backend.report.html.trend;

        string makeFname(string name) {
            return buildPath(ctx.state.get.logDir, name ~ HtmlStyle.ext);
        }

        auto collector = ctx.self.homeSystem.spawn(&spawnAnalyzeReportCollector,
                ctx.state.get.flow);

        runAnalyzer!makeStats(ctx.self, ctx.state.get.flow, collector,
                SubContent("Overview", "#overview", null), dbPath, ctx.state.get.kinds,
                AbsolutePath(ctx.state.get.logDir ~ Path("worklist" ~ HtmlStyle.ext)));

        runAnalyzer!makeMutantPage(ctx.self, ctx.state.get.flow, collector,
                SubContent("Mutants", "#mutants", null), dbPath, ctx.state.get.conf,
                ctx.state.get.kinds,
                AbsolutePath(ctx.state.get.logDir ~ Path("mutants" ~ HtmlStyle.ext)));

        runAnalyzer!makeTestCases(ctx.self, ctx.state.get.flow, collector,
                SubContent("Test Cases", "#test_cases", null), dbPath, ctx.state.get.conf,
                ctx.state.get.kinds, ctx.state.get.metaData, ctx.state.get.logTestCasesDir);

        if (ReportSection.trend in ctx.state.get.sections) {
            runAnalyzer!makeTrend(ctx.self, ctx.state.get.flow, collector,
                    SubContent("Trend", "#trend", null), dbPath, ctx.state.get.kinds);
        }

        if (!ctx.state.get.diff.empty) {
            runAnalyzer!makeDiffView(ctx.self, ctx.state.get.flow, collector,
                    SubPage(makeFname("diff_view"), "Diff View"), dbPath, ctx.state.get.conf,
                    ctx.state.get.humanReadableKinds, ctx.state.get.kinds,
                    ctx.state.get.diff, ctx.fio.getOutputDir);
        }
        if (ReportSection.tc_groups in ctx.state.get.sections) {
            runAnalyzer!makeTestGroups(ctx.self, ctx.state.get.flow, collector,
                    SubPage(makeFname("test_groups"), "Test Groups"), dbPath,
                    ctx.state.get.conf, ctx.state.get.humanReadableKinds, ctx.state.get.kinds);
        }

        if (ReportSection.tc_min_set in ctx.state.get.sections) {
            runAnalyzer!makeMinimalSetAnalyse(ctx.self, ctx.state.get.flow, collector,
                    SubPage(makeFname("minimal_set"), "Minimal Test Set"), dbPath,
                    ctx.state.get.conf, ctx.state.get.humanReadableKinds, ctx.state.get.kinds);
        }

        if (ReportSection.tc_groups_similarity in ctx.state.get.sections) {
            runAnalyzer!makeTestGroupSimilarityAnalyse(ctx.self, ctx.state.get.flow, collector,
                    SubPage(makeFname("test_group_similarity"), "Test Group Similarity"), dbPath,
                    ctx.state.get.conf, ctx.state.get.humanReadableKinds, ctx.state.get.kinds);
        }

        runAnalyzer!makeNomut(ctx.self, ctx.state.get.flow, collector,
                SubPage(makeFname("nomut"), "NoMut Details"), dbPath, ctx.state.get.conf,
                ctx.state.get.humanReadableKinds, ctx.state.get.kinds);

        send(collector, DoneStartingReportersMsg.init);

        ctx.self.request(collector, infTimeout).send(GetPagesMsg.init)
            .capture(ctx).then((ref Ctx ctx, SubPage[] sp, SubContent[] sc) {
                ctx.state.get.subPages = sp;
                ctx.state.get.subContent = sc;
                ctx.state.get.reportsDone = true;
                send(ctx.self, IndexWaitMsg.init);
            });
    }

    static void startFileReportes(ref Ctx ctx, StartReporterMsg, AbsolutePath dbPath) {
        foreach (f; ctx.state.get.db.getDetailedFiles) {
            auto fa = ctx.self.homeSystem.spawn(&spawnFileReport,
                    ctx.state.get.flow, ctx.state.get.fileCollector, dbPath,
                    ctx.fio.dup, ctx.state.get.kinds, ctx.state.get.conf,
                    ctx.state.get.logFilesDir, f);
            send(ctx.state.get.fileCollector, StartReporterMsg.init);
        }
        send(ctx.state.get.fileCollector, DoneStartingReportersMsg.init);

        ctx.self.request(ctx.state.get.fileCollector, infTimeout)
            .send(GetIndexesMsg.init).capture(ctx).then((ref Ctx ctx, FileIndex[] a) {
                ctx.state.get.files = a;
                ctx.state.get.filesDone = true;
                send(ctx.self, IndexWaitMsg.init);
            });
    }

    static void indexWait(ref Ctx ctx, IndexWaitMsg) {
        if (ctx.state.get.reportsDone && ctx.state.get.filesDone)
            send(ctx.self, GenerateIndexMsg.init);
    }

    static void checkDone(ref Ctx ctx, CheckDoneMsg) {
        if (!ctx.state.get.done) {
            delayedSend(ctx.self, delay(1.dur!"seconds"), CheckDoneMsg.init);
            return;
        }

        if (!ctx.state.get.waitForDone.empty)
            ctx.state.get.waitForDone.deliver(true);
    }

    static Promise!bool waitForDone(ref Ctx ctx, WaitForDoneMsg) {
        send(ctx.self, CheckDoneMsg.init);
        ctx.state.get.waitForDone = makePromise!bool;
        return ctx.state.get.waitForDone;
    }

    static void genIndex(ref Ctx ctx, GenerateIndexMsg) {
        scope (exit)
            () { ctx.state.get.done = true; send(ctx.self, CheckDoneMsg.init); }();

        import std.datetime : Clock;
        import dextool.plugin.mutate.backend.report.html.page_tree_map;

        auto profile = Profile("post process report");

        auto index = makeDashboard;
        index.title = format("Mutation Testing Report %(%s %) %s",
                ctx.state.get.humanReadableKinds, Clock.currTime);

        auto content = index.mainBody.getElementById("content");

        NavbarItem[] navbarItems;
        void addSubPage(Fn)(Fn fn, string name, string linkTxt) {
            const fname = buildPath(ctx.state.get.logDir, name ~ HtmlStyle.ext);
            logger.infof("Generating %s (%s)", linkTxt, name);
            File(fname, "w").write(fn());
            navbarItems ~= NavbarItem(linkTxt, fname.baseName);
        }

        // content must be added in a specific order such as statistics first
        SubContent[string] subContent;
        foreach (sc; ctx.state.get.subContent)
            subContent[sc.tag] = sc;
        void addContent(string tag) {
            auto item = subContent[tag];
            navbarItems ~= NavbarItem(item.name, tag);
            content.addChild(new RawSource(index, item.content));
            subContent.remove(tag);
        }

        addContent("#overview");
        // add files here to force it to always be after the overview.
        navbarItems ~= NavbarItem("Files", "#files");

        foreach (tag; subContent.byKey.array.sort)
            addContent(tag);

        foreach (sp; ctx.state.get.subPages.sort!((a, b) => a.fileName < b.fileName)) {
            const link = relativePath(sp.fileName, ctx.state.get.logDir);
            navbarItems ~= NavbarItem(sp.linkTxt, link);
        }

        // keep
        if (ReportSection.treemap in ctx.state.get.sections) {
            addSubPage(() => makeTreeMapPage(ctx.state.get.files), "tree_map", "Treemap");
        }

        ctx.state.get.files.toIndex(content, HtmlStyle.fileDir);

        addNavbarItems(navbarItems, index.mainBody.getElementById("navbar-sidebar"));

        File(buildPath(ctx.state.get.logDir, "index" ~ HtmlStyle.ext), "w").write(
                index.toPrettyString);
    }

    self.exceptionHandler = toDelegate(&logExceptionHandler);
    send(self, InitMsg.init, dbPath);
    return impl(self, &init_, capture(st), &startFileReportes, capture(st),
            &waitForDone, capture(st), &checkDone, capture(st), &genIndex,
            capture(st), &startAnalyzers, capture(st), &indexWait, capture(st));
}

void runAnalyzer(alias fn, Args...)(OverviewActor.Impl self, FlowControlActor.Address flow,
        AnalyzeReportCollectorActor.Address collector, SubPage sp,
        AbsolutePath dbPath, auto ref Args args) @trusted {
    // keep params separated because it is easier to forward the captured arguments to `fn`.
    auto params = tuple(args);
    auto ctx = tuple!("self", "collector", "sp", "db")(self, collector, sp, dbPath);

    // wait for flow to return a token.
    // then start the analyzer and send the result to the collector.
    send(collector, StartReporterMsg.init);

    self.request(flow, infTimeout).send(TakeTokenMsg.init).capture(params, ctx)
        .then((ref Tuple!(typeof(params), typeof(ctx)) ctx, my.actor.utility.limiter.Token _) {
            // actor spawned in the system that will run the analyze. Uses a
            // dynamic actor because then we do not need to make an interface.
            // It should be OK because it is only used here, not as a generic
            // actor. The "type checking" is done when `fn` is called which
            // ensure that the captured parameters match.
            ctx[1].self.homeSystem.spawn((Actor* self, typeof(params) params, typeof(ctx[1]) ctx) {
                // tells the actor to actually do the work
                send(self, self, ctx.db, ctx.collector, ctx.sp);
                return impl(self, (ref typeof(params) ctx, Actor* self, AbsolutePath dbPath,
                AnalyzeReportCollectorActor.Address collector, SubPage sp) {
                    auto db = Database.make(dbPath);
                    auto content = fn(db, ctx.expand);
                    File(sp.fileName, "w").write(content);
                    send(collector, sp);
                    self.shutdown;
                }, capture(params));
            }, ctx[0], ctx[1]);
        });
}

void runAnalyzer(alias fn, Args...)(OverviewActor.Impl self, FlowControlActor.Address flow,
        AnalyzeReportCollectorActor.Address collector, SubContent sc,
        AbsolutePath dbPath, auto ref Args args) @trusted {
    import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage;

    // keep params separated because it is easier to forward the captured arguments to `fn`.
    auto params = tuple(args);
    auto ctx = tuple!("self", "collector", "sc", "db")(self, collector, sc, dbPath);

    // wait for flow to return a token.
    // then start the analyzer and send the result to the collector.
    send(collector, StartReporterMsg.init);

    self.request(flow, infTimeout).send(TakeTokenMsg.init).capture(params, ctx)
        .then((ref Tuple!(typeof(params), typeof(ctx)) ctx, my.actor.utility.limiter.Token _) {
            // actor spawned in the system that will run the analyze. Uses a
            // dynamic actor because then we do not need to make an interface.
            // It should be OK because it is only used here, not as a generic
            // actor. The "type checking" is done when `fn` is called which
            // ensure that the captured parameters match.
            ctx[1].self.homeSystem.spawn((Actor* self, typeof(params) params, typeof(ctx[1]) ctx) {
                // tells the actor to actually do the work
                send(self, self, ctx.db, ctx.collector, ctx.sc);
                return impl(self, (ref typeof(params) ctx, Actor* self, AbsolutePath dbPath,
                AnalyzeReportCollectorActor.Address collector, SubContent sc) {
                    auto db = Database.make(dbPath);
                    auto doc = tmplBasicPage;
                    auto root = doc.mainBody.addChild("div");
                    fn(db, sc.tag, root, ctx.expand);
                    sc.content = root.toPrettyString;
                    send(collector, sc);
                    self.shutdown;
                }, capture(params));
            }, ctx[0], ctx[1]);
        });
}
