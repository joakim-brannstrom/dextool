/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains a parser of diffs in the Unified Format.
It is pretty limited because it only handles those that git normally output.
The result are which lines has changes in what files.

https://www.gnu.org/software/diffutils/manual/html_node/Detailed-Unified.html#Detailed-Unified

Example:
---
-- a/plugin/mutate/source/dextool/plugin/mutate/backend/database/standalone.d
++ b/plugin/mutate/source/dextool/plugin/mutate/backend/database/standalone.d
@@ -31,7 +31,6 @@ import std.algorithm : map;
 import std.array : Appender, appender, array;
 import std.datetime : SysTime;
 import std.format : format;
-import std.typecons : Tuple;

 import d2sqlite3 : sqlDatabase = Database;

@@ -46,7 +45,7 @@ import dextool.plugin.mutate.backend.type : Language;
 struct Database {
     import std.conv : to;
     import std.exception : collectException;
-    import std.typecons : Nullable;
+    import std.typecons : Nullable, Flag, No;
     import dextool.plugin.mutate.backend.type : MutationPoint, Mutation, Checksum;

     sqlDatabase db;
---
*/
module dextool.plugin.mutate.backend.diff_parser;

import logger = std.experimental.logger;
import std.path : buildPath;
import std.range : ElementType;
import std.traits : isSomeString;

import dextool.type : AbsolutePath, Path;

version (unittest) {
    import unit_threaded : shouldEqual, shouldBeTrue, should;
}

Diff diffFromStdin() @trusted {
    import std.stdio : stdin;
    import dextool.plugin.mutate.backend.diff_parser : UnifiedDiffParser;

    return toDiff(stdin.byLine);
}

/** Parse a range of lines to a diff.
 *
 * Params:
 *  r = range of strings which is the diff
 */
Diff toDiff(Range)(Range r) if (isSomeString!(ElementType!Range)) {
    UnifiedDiffParser parser;
    foreach (l; r) {
        debug logger.trace(l);
        parser.process(l);
    }
    return parser.result;
}

@safe:

struct Diff {
    import my.set;

    static struct Line {
        uint line;
        string text;
    }

    /// The raw diff that where parsed.
    Line[][Path] rawDiff;

    alias ChangedLines = Set!uint;

    ChangedLines[Path] changes;
    alias changes this;

    bool empty() @safe pure nothrow const @nogc {
        return changes.length == 0;
    }

    /** A range over the changes by file.
     *
     * The paths are adjusted to be relative `workdir`.
     */
    auto toRange(AbsolutePath workdir) @safe {
        return DiffRange(this, workdir);
    }
}

struct DiffRange {
    import std.path : relativePath;
    import std.array : array;
    import my.set;

    static struct KeyValue {
        Path key;
        Diff.ChangedLines value;
        AbsolutePath absPath;
    }

    private {
        Diff diff;
        AbsolutePath workdir;
        Path[] keys;
    }

    this(Diff d, AbsolutePath workdir) {
        this.diff = d;
        this.workdir = workdir;
        this.keys = diff.byKey.array;
        debug logger.trace(workdir);
    }

    KeyValue front() @safe {
        assert(!empty, "Can't get front of an empty range");
        debug logger.trace(keys[0]);
        return KeyValue(keys[0], diff[keys[0]], AbsolutePath(buildPath(workdir, keys[0])));
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        keys = keys[1 .. $];
    }

    bool empty() @safe pure nothrow const @nogc {
        return keys.length == 0;
    }
}

/** Parse a buffer in the Unified diff format and return the hunks of changes
 * in the targets.
 */
struct UnifiedDiffParser {
    import std.regex : Regex, regex, matchFirst, matchAll;
    import std.typecons : Tuple;

    Diff result;

    private {
        // diff --git a/usability/report.md b/usability/report.md
        Regex!char re_git_diff_hdr = regex(`^diff --git.*`);
        // --- a/standalone.d
        Regex!char re_hdr_original = regex(`^--- (?P<hdr>.*)`);
        // +++ a/standalone.d
        Regex!char re_hdr_new = regex(`^\+\+\+ (?P<hdr>.*)`);
        // @@ -31,7 +31,6 @@ import std.algorithm : map;
        Regex!char re_hunk_start_multiline = regex(
                `^@@ -\d*,\d* \+(?P<line>\d*),(?P<count>\d*) @@.*`);
        // @@ -31 +31 @@ import std.algorithm : map;
        Regex!char re_hunk_start_line = regex(`^@@ -\d* \+(?P<line>\d*) @@.*`);

        alias FsmState = Tuple!(bool, State, Action[]);

        FsmState st;
        StateData data;
        bool isGitDiff;
    }

    void process(T)(T line) {
        import std.conv : to;
        import std.meta;
        import std.traits : EnumMembers;
        import std.string : startsWith, split;
        import dextool.type : Path, AbsolutePath;
        import my.set;

        auto is_git_diff = !matchFirst(line, re_git_diff_hdr).empty;
        auto hdr_original = matchFirst(line, re_hdr_original);
        auto hdr_new = matchFirst(line, re_hdr_new);
        auto hunk_start_multiline = matchFirst(line, re_hunk_start_multiline);
        auto hunk_start_line = matchFirst(line, re_hunk_start_line);
        const first_char = line.length != 0 ? line[0] : typeof(line[0]).init;

        FsmState nextState(const State st) {
            auto next = FsmState(false, st, null);

            final switch (st) {
            case State.findHdr:
                if (is_git_diff) {
                    next[1] = State.findHdrOriginal;
                    next[2] = [Action.setGitDiff];
                } else if (!hdr_original.empty) {
                    next[0] = true;
                    next[1] = State.findHdrOriginal;
                }
                break;
            case State.findHdrOriginal:
                if (!hdr_original.empty) {
                    next[1] = State.findHdrNew;
                    next[2] = [Action.resetStateData, Action.saveOriginal];
                }
                break;
            case State.findHdrNew:
                if (!hdr_new.empty) {
                    next[1] = State.checkOrigNew;
                    next[2] = [Action.saveNew];
                    next[0] = true;
                }
                break;
            case State.checkOrigNew:
                if (data.hdrOriginal.length == 0) {
                    next[1] = State.findHdrOriginal;
                    next[2] = [Action.warnOriginal];
                } else if (data.hdrNew.length == 0) {
                    next[1] = State.findHdrOriginal;
                    next[2] = [Action.warnNew];
                } else {
                    next[1] = State.findHunkStart;
                }
                break;
            case State.findNext:
                if (!hunk_start_multiline.empty || !hunk_start_line.empty) {
                    next[1] = State.findHunkStart;
                    next[0] = true;
                } else if (!hdr_original.empty) {
                    next[1] = State.findHdrOriginal;
                    next[0] = true;
                }
                break;
            case State.findHunkStart:
                if (!hunk_start_multiline.empty) {
                    next[1] = State.insideHunk;
                    next[2] = [Action.multiLineHunk];
                } else if (!hunk_start_line.empty) {
                    next[1] = State.insideHunk;
                    next[2] = [Action.lineHunk];
                }
                break;
            case State.insideHunk:
                next[2] = [Action.saveRawDiff];
                if (first_char == '+')
                    next[2] ~= [Action.plusLine];
                else if (first_char == ' ' || line.length == 0)
                    next[2] ~= [Action.blankLine];
                next[1] = State.checkHunkCounter;
                next[0] = true;
                break;
            case State.checkHunkCounter:
                next[1] = State.insideHunk;
                if (data.count == data.maxCount)
                    next[1] = State.findNext;
                break;
            }

            return next;
        }

        void resetStateDataAct() {
            data = StateData.init;
        }

        void saveOriginalAct() {
            auto a = hdr_original["hdr"];
            auto p = () {
                if (isGitDiff && a.length > 2)
                    return a[2 .. $].split('\t');
                return a.split('\t');
            }();

            data.hdrOriginal = Path(p[0].idup);
        }

        void saveNewAct() {
            auto a = hdr_new["hdr"];
            auto p = () {
                if (isGitDiff && a.length > 2)
                    return a[2 .. $].split('\t');
                return a.split('\t');
            }();

            data.hdrNew = Path(p[0].idup);
        }

        void warnOriginalAct() {
            logger.warning(
                    "Broken diff data. The original file, as specificed after ---, has length zero");
        }

        void warnNewAct() {
            logger.warning(
                    "Broken diff data. The new file, as specificed after +++, has length zero");
        }

        void multiLineHunkAct() {
            try {
                data.startPos = hunk_start_multiline["line"].to!uint;
                data.maxCount = hunk_start_multiline["count"].to!uint;
                data.count = 0;
            } catch (Exception e) {
                logger.info(e.msg);
                logger.info("Unable to parse diff line: ", line);
            }
        }

        void lineHunkAct() {
            try {
                data.startPos = hunk_start_multiline["line"].to!uint;
                data.maxCount = 1;
                data.count = 0;
            } catch (Exception e) {
                logger.info(e.msg);
                logger.info("Unable to parse diff line: ", line);
            }
        }

        void plusLineAct() {
            if (data.hdrNew !in result.changes)
                result[data.hdrNew] = Diff.ChangedLines.init;
            result[data.hdrNew].add(data.startPos + data.count);
            data.count++;
        }

        void blankLineAct() {
            data.count++;
        }

        void setGitDiffAct() {
            isGitDiff = true;
        }

        void saveRawDiffAct() {
            result.rawDiff[data.hdrNew] ~= Diff.Line(data.startPos + data.count, line.idup);
        }

        st[0] = true;
        while (st[0]) {
            st = nextState(st[1]);
            debug logger.tracef("%s | %s", line, st);

            foreach (const act; st[2]) {
                static foreach (Member; [EnumMembers!Action]) {
                    if (act == Member)
                        mixin(Member.to!string ~ "Act();");
                }
            }
            debug logger.tracef("%s | %s %s", result, data, isGitDiff);
        }
    }
}

private:

struct StateData {
    Path hdrOriginal;
    Path hdrNew;
    uint startPos;
    uint maxCount;
    uint count;
}

enum State {
    findHdr,
    findHdrOriginal,
    findHdrNew,
    checkOrigNew,
    findHunkStart,
    insideHunk,
    findNext,
    checkHunkCounter,
}

enum Action {
    setGitDiff,
    resetStateData,
    saveOriginal,
    saveNew,
    warnOriginal,
    warnNew,
    multiLineHunk,
    lineHunk,
    plusLine,
    blankLine,
    saveRawDiff,
}

version (unittest) {
    import std.string : lineSplitter;
    import my.set;
    import dextool.type;
}

@("shall detect the changes lines (unified git diff)")
unittest {
    immutable lines = `diff --git a/standalone2.d b/standalone2.d
index 0123..2345 100644
--- a/standalone.d
+++ b/standalone2.d
@@ -31,7 +31,6 @@ import std.algorithm : map;
 import std.array : Appender, appender, array;
 import std.datetime : SysTime;
+import std.format : format;
-import std.typecons : Tuple;

 import d2sqlite3 : sqlDatabase = Database;

@@ -46,7 +45,7 @@ import dextool.plugin.mutate.backend.type : Language;
 struct Database {
     import std.conv : to;
     import std.exception : collectException;
-    import std.typecons : Nullable;
+    import std.typecons : Nullable, Flag, No;
     import dextool.plugin.mutate.backend.type : MutationPoint, Mutation, Checksum;

+    sqlDatabase db;`;

    UnifiedDiffParser p;
    foreach (line; lines.lineSplitter)
        p.process(line);

    // assert
    p.result[Path("standalone2.d")].contains(33).shouldBeTrue;
    p.result[Path("standalone2.d")].contains(48).shouldBeTrue;
    p.result[Path("standalone2.d")].contains(51).shouldBeTrue;
    p.result.length.should == 1;
}

@("shall detect the changed lines (unified with date)")
unittest {

    immutable lines = `--- plugin/mutate/testdata/report_one_ror_mutation_point.cpp	2018-11-18 21:25:46.631640690 +0100
+++ plugin/mutate/testdata/report_one_ror_mutation_point2.cpp	2018-11-18 21:26:17.003691847 +0100
@@ -3,7 +3,7 @@
 /// @author Joakim Brännström (joakim.brannstrom@gmx.com)

 int fun(int x) {
-    if (x > 3) {
+    if (x != 3) {
         return 0;
     }
     return 1;`;

    UnifiedDiffParser p;
    foreach (line; lines.lineSplitter)
        p.process(line);

    // assert
    p.result[Path("plugin/mutate/testdata/report_one_ror_mutation_point2.cpp")].contains(6)
        .shouldBeTrue;
    p.result.length.should == 1;
}
