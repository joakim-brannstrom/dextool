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
```
--- a/plugin/mutate/source/dextool/plugin/mutate/backend/database/standalone.d
+++ b/plugin/mutate/source/dextool/plugin/mutate/backend/database/standalone.d
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
```
*/
module dextool.plugin.mutate.backend.diff_parser;

import logger = std.experimental.logger;

version (unittest) {
    import unit_threaded : shouldEqual, shouldBeTrue, should;
}

struct Diff {
    import dextool.type : Path;
    import dextool.set;

    alias ChangedLines = Set!uint;

    ChangedLines[Path] changes;
    alias changes this;
}

/** Parse a buffer in the Unified diff format and return the hunks of changes
 * in the targets.
 */
struct UnifiedDiffParser {
    import std.regex : ctRegex, matchFirst, matchAll;
    import std.typecons : Tuple;

    Diff result;

    private {
        // --- a/standalone.d
        enum re_hdr_original = ctRegex!(`^--- a/(?P<hdr>.*)`);
        // +++ a/standalone.d
        enum re_hdr_new = ctRegex!(`^\+\+\+ b/(?P<hdr>.*)`);
        // @@ -31,7 +31,6 @@ import std.algorithm : map;
        enum re_hunk_start_multiline = ctRegex!(`^@@ -\d*,\d* \+(?P<line>\d*),(?P<count>\d*) @@.*`);
        // @@ -31 +31 @@ import std.algorithm : map;
        enum re_hunk_start_line = ctRegex!(`^@@ -\d* \+(?P<line>\d*) @@.*`);

        alias FsmState = Tuple!(bool, State, Action[]);

        FsmState st;
        StateData data;
    }

    void process(T)(T line) {
        import std.conv : to;
        import std.meta;
        import std.traits : EnumMembers;
        import dextool.type : Path;
        import dextool.set;

        auto hdr_original = matchFirst(line, re_hdr_original);
        auto hdr_new = matchFirst(line, re_hdr_new);
        auto hunk_start_multiline = matchFirst(line, re_hunk_start_multiline);
        auto hunk_start_line = matchFirst(line, re_hunk_start_line);
        const first_char = line.length != 0 ? line[0] : typeof(line[0]).init;

        FsmState nextState(const State st) {
            auto next = FsmState(false, st, null);

            final switch (st) {
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
                if (first_char == '+')
                    next[2] = [Action.plusLine];
                else if (first_char == ' ' || line.length == 0)
                    next[2] = [Action.blankLine];
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
            data.hdrOriginal = Path(hdr_original["hdr"]);
        }

        void saveNewAct() {
            data.hdrNew = Path(hdr_new["hdr"]);
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
            data.startPos = hunk_start_multiline["line"].to!uint;
            data.maxCount = hunk_start_multiline["count"].to!uint;
            data.count = 0;
        }

        void lineHunkAct() {
            data.startPos = hunk_start_multiline["line"].to!uint;
            data.maxCount = 1;
            data.count = 0;
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

        st[0] = true;
        while (st[0]) {
            st = nextState(st[1]);
            logger.tracef("%s | %s", line, st);

            foreach (const act; st[2]) {
                static foreach (Member; [EnumMembers!Action]) {
                    if (act == Member)
                        mixin(Member.to!string ~ "Act();");
                }
            }
            logger.tracef("%s | %s", result, data);
        }
    }
}

private:

struct StateData {
    import dextool.type : Path;

    Path hdrOriginal;
    Path hdrNew;
    uint startPos;
    uint maxCount;
    uint count;
}

enum State {
    findHdrOriginal,
    findHdrNew,
    checkOrigNew,
    findHunkStart,
    insideHunk,
    findNext,
    checkHunkCounter,
}

enum Action {
    resetStateData,
    saveOriginal,
    saveNew,
    warnOriginal,
    warnNew,
    multiLineHunk,
    lineHunk,
    plusLine,
    blankLine,
}

@("shall detect the changes lines")
unittest {
    import std.string;
    import std.ascii : newline;
    import dextool.set;
    import dextool.type;

    immutable lines = `--- a/standalone.d
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
    logger.trace(p.result);
    p.result[Path("standalone2.d")].contains(33).shouldBeTrue;
    p.result[Path("standalone2.d")].contains(48).shouldBeTrue;
    p.result[Path("standalone2.d")].contains(51).shouldBeTrue;
    p.result.length.should == 1;
}
