/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains utility functions used by different reports and analyzers
such as type converters, string manipulations etc.
*/
module dextool.plugin.mutate.backend.report.utility;

import logger = std.experimental.logger;
import std.exception : collectException;
import std.typecons : Flag, Yes, No;

import dextool.plugin.mutate.backend.database : Database, spinSql, MutationId;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Mutation, Offset, TestCase, Language, TestGroup;
import dextool.plugin.mutate.type : ReportKillSortOrder;
import dextool.plugin.mutate.type : ReportLevel, ReportSection;
import dextool.type;

// 5 because it covers all the operators and true/false
immutable windowSize = 5;

immutable invalidFile = "Dextool: Invalid UTF-8 content";

/// Create a range from `a` that has at most maxlen+3 letters in it.
string window(T)(T a, size_t maxlen = windowSize) {
    import std.algorithm : filter, among;
    import std.conv : text;
    import std.range : take, chain;
    import std.uni : byGrapheme, byCodePoint;
    import dextool.plugin.mutate.backend.type : invalidUtf8;

    try {
        return chain(a.byGrapheme.take(maxlen)
                .byCodePoint.filter!(a => !a.among('\n')).text, a.length > maxlen ? "..." : null)
            .text;
    } catch (Exception e) {
        return invalidUtf8;
    }
}

ReportSection[] toSections(const ReportLevel l) @safe {
    ReportSection[] secs;
    final switch (l) with (ReportSection) {
    case ReportLevel.summary:
        secs = [summary];
        break;
    case ReportLevel.alive:
        secs = [summary, mut_stat, tc_killed_no_mutants, tc_full_overlap, alive];
        break;
    case ReportLevel.all:
        secs = [
            summary, mut_stat, all_mut, tc_killed, tc_killed_no_mutants,
            tc_full_overlap
        ];
        break;
    }

    return secs;
}

string toInternal(ubyte[] data) @safe nothrow {
    import std.utf : validate;

    try {
        auto result = () @trusted { return cast(string) data; }();
        validate(result);
        return result;
    } catch (Exception e) {
    }

    return invalidFile;
}

struct Table(int columnsNr) {
    alias Row = string[columnsNr];

    Row heading_;
    Row[] rows;
    ulong[columnsNr] columnWidth;

    this(const Row heading) @safe {
        this.heading = heading;
        updateColumns(heading);
    }

    bool empty() @safe pure nothrow const @nogc {
        return rows.length == 0;
    }

    void heading(const Row r) @safe {
        heading_ = r;
        updateColumns(r);
    }

    void put(const Row r) @safe {
        rows ~= r;
        updateColumns(r);
    }

    import std.format : FormatSpec;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.ascii : newline;
        import std.range : enumerate, repeat;
        import std.format : formattedWrite;
        import std.range.primitives : put;

        immutable sep = "|";
        immutable lhs_sep = "| ";
        immutable mid_sep = " | ";
        immutable rhs_sep = " |";

        void printRow(const ref Row r) {
            foreach (const r_; r[].enumerate) {
                if (r_.index == 0)
                    put(w, lhs_sep);
                else
                    put(w, mid_sep);
                formattedWrite(w, "%-*s", columnWidth[r_.index], r_.value);
            }
            put(w, rhs_sep);
            put(w, newline);
        }

        printRow(heading_);

        immutable dash = "-";
        foreach (len; columnWidth) {
            put(w, sep);
            put(w, repeat(dash, len + 2));
        }
        put(w, sep);
        put(w, newline);

        foreach (const ref r; rows) {
            printRow(r);
        }
    }

    private void updateColumns(const ref Row r) @safe {
        import std.algorithm : filter, count, map;
        import std.range : enumerate;
        import std.utf : byCodeUnit;
        import std.typecons : tuple;

        foreach (a; r[].enumerate
                .map!(a => tuple(a.index, a.value.byCodeUnit.count))
                .filter!(a => a[1] > columnWidth[a[0]])) {
            columnWidth[a[0]] = a[1];
        }
    }
}

string statusToString(Mutation.Status status) @trusted {
    import std.conv : to;

    return to!string(status);
}

string statusToString(ulong status) @trusted {
    import std.conv : to;

    return statusToString(status.to!(Mutation.Status));
}

string kindToString(Mutation.Kind kind) @trusted {
    import std.conv : to;

    return to!string(kind);
}

string kindToString(long kind) @trusted {
    import std.conv : to;

    return kindToString(kind.to!(Mutation.Kind));
}
