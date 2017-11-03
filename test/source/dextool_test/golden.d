/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool_test.golden;

import scriptlike;

struct BuildCompare {
    import std.typecons : Yes, No;

    private {
        string outdir_;

        Flag!"sortLines" sort_lines = No.sortLines;
        Flag!"skipComments" skip_comments = Yes.skipComments;

        /// if the output from running the command should be yapped via scriptlike
        bool yap_output = true;

        /// Throw an exception if a compare failes
        bool throw_on_failed_compare_ = true;

        GoldResult[] gold_results;
    }

    private static struct GoldResult {
        Path gold;
        Path result;
    }

    this(string outdir) {
        this.outdir_ = outdir;
    }

    Path outdir() {
        return Path(outdir_);
    }

    auto addCompare(Path gold, string result_file) {
        this.gold_results ~= GoldResult(gold, buildPath(outdir_, result_file).Path);
        return this;
    }

    auto sortLines(bool v) {
        sort_lines = cast(Flag!"sortLines") v;
        return this;
    }

    auto skipComments(bool v) {
        skip_comments = cast(Flag!"skipComments") v;
        return this;
    }

    auto throwOnFailure(bool v) {
        this.throw_on_failed_compare_ = v;
        return this;
    }

    auto run() {
        CompareResult res;

        foreach (const ref gr; gold_results) {
            res = compare(gr.gold, gr.result, sort_lines, skip_comments);
            if (!res.status) {
                break;
            }
        }

        if (!res.status && yap_output) {
            File(nextFreeLogfile(outdir_), "w").writef("%s", res);
        }

        if (!res.status && throw_on_failed_compare_) {
            throw new ErrorLevelException(1, res.errorMsg);
        }

        return res;
    }
}

/** Sorted compare of gold and result.
 *
 * max_diff is arbitrarily chosen to 5.
 * The purpose is to limit the amount of text that is dumped.
 * The reasoning is that it is better to give more than one line as feedback.
 */
private CompareResult compare(const Path gold, const Path result,
        Flag!"sortLines" sortLines, Flag!"skipComments" skipComments) {
    import std.format : format;
    import std.stdio : File;
    import dextool_test.utils : escapePath, removeJunk;

    CompareResult res;

    res.msg ~= "Comparing gold:" ~ gold.raw;
    res.msg ~= "        result:" ~ result.raw;

    File goldf;
    File resultf;

    try {
        goldf = File(gold.escapePath);
        resultf = File(result.escapePath);
    }
    catch (ErrnoException ex) {
        res.errorMsg = ex.msg;
        res.status = false;
        return res;
    }

    auto maybeSort(T)(T lines) {
        import std.array : array;
        import std.algorithm : sort;

        if (sortLines) {
            return sort!((a, b) => a[1] < b[1])(lines.array()).array();
        }

        return lines.array();
    }

    bool diff_detected = false;
    immutable max_diff = 5;
    int accumulated_diff;
    // dfmt off
    foreach (g, r;
             lockstep(maybeSort(goldf
                                .byLineCopy()
                                .enumerate
                                .removeJunk(skipComments)),
                      maybeSort(resultf
                                .byLineCopy()
                                .enumerate
                                .removeJunk(skipComments))
                      )) {
        if (g[1] != r[1] && accumulated_diff < max_diff) {
            // +1 of index because editors start counting lines from 1
            res.lineDiff ~= format("Line %s gold: %s", g[0] + 1, g[1]);
            res.lineDiff ~= format("Line %s  out: %s", r[0] + 1, r[1]);
            diff_detected = true;
            ++accumulated_diff;
        }
    }
    // dfmt on

    res.status = !diff_detected;

    if (diff_detected) {
        res.errorMsg = "Output is different from reference file (gold): " ~ gold.escapePath;
    }

    return res;
}

struct CompareResult {
    import std.ascii : newline;
    import std.format : FormatSpec;

    // true if the golden file and result are _equal_.
    bool status;

    string errorMsg;
    string[] msg;
    string[] lineDiff;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range.primitives : put;

        formattedWrite(w, "status: %s\n", status);

        if (errorMsg.length) {
            put(w, errorMsg);
            put(w, newline);
        }

        this.msg.each!((a) { put(w, a); put(w, newline); });
        this.lineDiff.each!((a) { put(w, a); put(w, newline); });
    }

    string toString() @safe pure const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
}

private auto nextFreeLogfile(string outdir) {
    import std.file : exists;
    import std.path : baseName;
    import std.string : format;

    int idx;
    string f;
    do {
        f = buildPath(outdir, format("run_compare%s.log", idx));
        ++idx;
    }
    while (exists(f));

    return f;
}
