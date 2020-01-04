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
import dextool.plugin.mutate.backend.type : Mutation, Offset, SourceLoc, Token;
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
                : conf.reportSection.dup).toSet;
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
        import dextool.plugin.mutate.backend.report.analyzers : reportStatistics;

        const original = fr.file.dup.pathToHtml;
        const report = (original ~ htmlExt).Path;

        auto stat = reportStatistics(db, kinds, fr.file);

        files.put(FileIndex(report, fr.file, stat.alive,
                stat.killed + stat.timeout + stat.aliveNoMut, stat.total, stat.aliveNoMut));

        const out_path = buildPath(logFilesDir, report).Path.AbsolutePath;

        auto raw = fio.makeInput(AbsolutePath(fr.file, DirName(fio.getOutputDir)));

        auto tc_info = db.getAllTestCaseInfo2(fr.id, kinds);

        ctx = FileCtx.make(original, fr.id, raw, tc_info);
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
        static string cleanup(const(char)[] raw) @safe nothrow {
            import std.algorithm : filter;
            import std.array : array;
            import std.utf : byChar;

            return raw.byChar.filter!(a => a != '\0').array.idup;
        }

        auto txt = makeMutationText(ctx.raw, fr.mutationPoint.offset, fr.mutation.kind, fr.lang);
        ctx.span.put(FileMutant(fr.id, fr.mutationPoint.offset,
                cleanup(txt.original), cleanup(txt.mutation), fr.mutation));
    }

    override void endFileEvent(ref Database db) @trusted {
        import std.algorithm : max, each, map, min, canFind, sort, filter;
        import std.array : appender, empty;
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
        auto lines = root.addChild("table").setAttribute("id", "locs");
        auto line = lines.addChild("tr").addChild("td").setAttribute("id", "loc-1");
        line.addClass("loc");

        line.addChild("span", "1:").addClass("line_nr");
        auto mut_data = "var g_muts_data = {};\n";
        mut_data ~= "g_muts_data[-1] = {'kind' : null, 'status' : null, 'testCases' : null, 'orgText' : null, 'mutText' : null, 'meta' : null};\n";

        // used to make sure that metadata about a mutant is only written onces
        // to the global arrays.
        Set!MutationId ids;
        auto muts = appender!(MData[])();

        // this is the last location. It is used to calculate the num of
        // newlines, detect when a line changes etc.
        auto lastLoc = SourceLoc(1, 1);

        foreach (const s; ctx.span.toRange) {
            if (s.tok.loc.line > lastLoc.line) {
                lastLoc.column = 1;
            }
            auto meta = MetaSpan(s.muts);

            foreach (const i; 0 .. max(0, s.tok.loc.line - lastLoc.line)) {
                with (line = lines.addChild("tr").addChild("td")) {
                    setAttribute("id", format("%s-%s", "loc", lastLoc.line + i + 1));
                    addClass("loc");
                    addChild("span", format("%s:", lastLoc.line + i + 1)).addClass("line_nr");
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
                if (s.muts.length != 0)
                    addClass(format("%(mutid%s %)", s.muts.map!(a => a.id)));
                if (meta.onClick.length != 0)
                    setAttribute("onclick", meta.onClick);
            }

            foreach (m; s.muts.filter!(m => !ids.contains(m.id))) {
                ids.add(m.id);

                muts.put(MData(m.id, m.txt, m.mut, db.getMutantationMetaData(m.id)));
                with (d0.addChild("span", m.mutation)) {
                    addClass("mutant");
                    addClass(s.tok.toName);
                    setAttribute("id", m.id.to!string);
                }
                d0.addChild("a").setAttribute("href", "#" ~ m.id.to!string);

                auto testCases = ctx.getTestCaseInfo(m.id);
                if (testCases.empty) {
                    mut_data ~= format("g_muts_data[%s] = {'kind' : %s, 'kindGroup' : %s, 'status' : %s, 'testCases' : null, 'orgText' : '%s', 'mutText' : '%s', 'meta' : '%s'};\n",
                            m.id, m.mut.kind.to!int, toUser(m.mut.kind)
                            .to!int, m.mut.status.to!ubyte, window(m.txt.original),
                            window(m.txt.mutation), db.getMutantationMetaData(m.id).kindToString);
                } else {
                    mut_data ~= format("g_muts_data[%s] = {'kind' : %s, 'kindGroup' : %s, 'status' : %s, 'testCases' : [%('%s',%)'], 'orgText' : '%s', 'mutText' : '%s', 'meta' : '%s'};\n",
                            m.id, m.mut.kind.to!int, toUser(m.mut.kind)
                            .to!int, m.mut.status.to!ubyte,
                            testCases.map!(a => a.name), window(m.txt.original),
                            window(m.txt.mutation), db.getMutantationMetaData(m.id).kindToString);
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
                    db.getDetectedTestCases().length)));
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
            appendChild(new RawSource(ctx.doc, mut_data));
            appendText("\n");
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
        import dextool.plugin.mutate.backend.report.html.page_minimal_set;
        import dextool.plugin.mutate.backend.report.html.page_nomut;
        import dextool.plugin.mutate.backend.report.html.page_diff;
        import dextool.plugin.mutate.backend.report.html.page_stats;
        import dextool.plugin.mutate.backend.report.html.page_test_case_similarity;
        import dextool.plugin.mutate.backend.report.html.page_test_case_unique;
        import dextool.plugin.mutate.backend.report.html.page_test_group_similarity;
        import dextool.plugin.mutate.backend.report.html.page_test_groups;
        import dextool.plugin.mutate.backend.report.html.page_tree_map;

        auto index = tmplBasicPage;
        index.title = format("Mutation Testing Report %(%s %) %s",
                humanReadableKinds, Clock.currTime);
        auto s = index.root.childElements("head")[0].addChild("script");
        s.addChild(new RawSource(index, js_index));

        void addSubPage(Fn)(Fn fn, string name, string link_txt) {
            import std.functional : unaryFun;

            const fname = buildPath(logDir, name ~ htmlExt);
            index.mainBody.addChild("p").addChild("a", link_txt).href = fname.baseName;
            logger.infof("Generating %s (%s)", link_txt, name);
            File(fname, "w").write(fn());
        }

        addSubPage(() => makeStats(db, conf, humanReadableKinds, kinds), "stats", "Statistics");
        if (!diff.empty) {
            addSubPage(() => makeDiffView(db, conf, humanReadableKinds, kinds,
                    diff, fio.getOutputDir), "diff_view", "Diff View");
        }
        addSubPage(() => makeLongTermView(db, conf, humanReadableKinds, kinds),
                "long_term_view", "Long Term View");
        if (ReportSection.treemap in sections) {
            addSubPage(() => makeTreeMapPage(files.data), "tree_map", "Treemap");
        }
        if (ReportSection.tc_groups in sections) {
            addSubPage(() => makeTestGroups(db, conf, humanReadableKinds,
                    kinds), "test_groups", "Test Groups");
        }
        addSubPage(() => makeNomut(db, conf, humanReadableKinds, kinds), "nomut", "NoMut Details");
        if (ReportSection.tc_min_set in sections) {
            addSubPage(() => makeMinimalSetAnalyse(db, conf, humanReadableKinds,
                    kinds), "minimal_set", "Minimal Test Set");
        }
        if (ReportSection.tc_similarity in sections) {
            addSubPage(() => makeTestCaseSimilarityAnalyse(db, conf, humanReadableKinds,
                    kinds), "test_case_similarity", "Test Case Similarity");
        }
        if (ReportSection.tc_groups_similarity in sections) {
            addSubPage(() => makeTestGroupSimilarityAnalyse(db, conf, humanReadableKinds,
                    kinds), "test_group_similarity", "Test Group Similarity");
        }
        if (ReportSection.tc_unique in sections) {
            addSubPage(() => makeTestCaseUnique(db, conf, humanReadableKinds,
                    kinds), "test_case_unique", "Test Case Uniqueness");
        }

        files.data.toIndex(index.mainBody, htmlFileDir);
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
        import std.algorithm : sort;
        import std.array : array;
        import dextool.plugin.mutate.backend.report.html.js;
        import dextool.plugin.mutate.backend.report.html.tmpl;

        auto r = FileCtx.init;
        r.doc = tmplBasicPage;
        r.doc.title = title;
        r.doc.mainBody.setAttribute("onload", "javascript:init();");

        auto s = r.doc.root.childElements("head")[0].addChild("style");
        s.addChild(new RawSource(r.doc, tmplIndexStyle));

        s = r.doc.root.childElements("head")[0].addChild("script");
        s.addChild(new RawSource(r.doc, js_source));

        r.doc.mainBody.appendHtml(tmplIndexBody);

        r.fileId = id;

        r.raw = raw;

        typeof(tcKilledMutant) tmp;
        foreach (a; tc_info) {
            foreach (mut; a.killed) {
                if (auto v = mut in tmp) {
                    *v ~= TestCaseInfo(a.name, a.killed.length);
                } else {
                    tmp[mut] = [TestCaseInfo(a.name, a.killed.length)];
                }
            }
            r.testCases ~= TestCaseInfo(a.name, a.killed.length);
        }
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
    import std.path : buildPath;
    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context;
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
    import std.algorithm : sort, filter;
    import std.conv : to;
    import std.path : buildPath;

    auto tbl_container = root.addChild("div").addClass("tbl_container");
    auto tbl = tmplDefaultTable(tbl_container, [
            "Path", "Score", "Alive", "NoMut", "Total"
            ]);

    // Users are not interested that files that contains zero mutants are shown
    // in the list. It is especially annoying when they are marked with dark
    // green.
    bool has_suppressed;
    foreach (f; files.sort!((a, b) => a.path < b.path)
            .filter!(a => a.totalMutants != 0)) {
        auto r = tbl.appendRow();
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
    root.setAttribute("onload", "init()");
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
        killedByCompiler,
        unknown,
        none,
    }

    StatusColor status;
    string onClick;

    this(const(FileMutant)[] muts) {
        immutable click_fmt2 = "ui_set_mut(%s)";
        status = StatusColor.none;

        foreach (ref const m; muts) {
            status = pickColor(m, status);
            if (onClick.length == 0 && m.mut.status == Mutation.Status.alive) {
                onClick = format(click_fmt2, m.id);
            }
        }

        if (onClick.length == 0 && muts.length != 0) {
            onClick = format(click_fmt2, muts[0].id);
        }
    }
}

/// Choose a color for a mutant span by prioritizing alive mutants above all.
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
