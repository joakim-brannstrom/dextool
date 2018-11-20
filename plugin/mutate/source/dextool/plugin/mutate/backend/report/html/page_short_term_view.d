/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_short_term_view;

import logger = std.experimental.logger;
import std.algorithm : sort, map, filter, count;
import std.conv : to;
import std.datetime : Clock, dur;
import std.format : format;
import std.typecons : tuple;
import std.xml : encode;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.nodes;
import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

@safe:

auto makeShortTermView(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds,
        ref Diff diff, AbsolutePath workdir) {
    import dextool.plugin.mutate.backend.report.html.tmpl : addStateTableCss;

    auto root = defaultHtml(format("Short Term View %(%s %) %s",
            humanReadableKinds, Clock.currTime));
    auto s = root.preambleBody.n("style".Tag);
    addStateTableCss(s);

    toHtml(reportDiff(db, kinds, diff, workdir), root.body_);

    return root;
}

private:

void toHtml(DiffReport report, HtmlNode root) {
    import std.array : array;
    import std.path : buildPath;
    import std.range : enumerate;
    import dextool.plugin.mutate.backend.mutation_type : toUser;

    root.n("h2".Tag).put("Code Changes");

    root.n("p".Tag)
        .put("This are the mutants on the lines that where changed in the supplied diff.");

    auto tbl = HtmlTable.make;
    root.put(tbl.root);
    tbl.root.putAttr("class", "overlap_tbl");
    foreach (c; ["File", "Alive", "Killed"])
        tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);

    foreach (const pkv; report.files
            .byKeyValue
            .map!(a => tuple(a.key, a.value.dup))
            .array
            .sort!((a, b) => a[1] < b[1])) {
        auto r = tbl.newRow;
        const path = report.files[pkv[0]];
        r.td.put(path);

        auto alive_ids = r.td;
        if (auto alive = pkv[0] in report.alive) {
            foreach (a; (*alive).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                alive_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                        format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                alive_ids.put(" ");
            }
        }

        auto killed_ids = r.td;
        if (auto killed = pkv[0] in report.killed) {
            foreach (a; (*killed).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                killed_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                        format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                killed_ids.put(" ");
            }
        }
    }

    root.n("p".Tag).put("This are the test cases that killed mutants in the code changes.")
        .put(format("%s test case(s) affected by the change", report.testCases.length));

    auto tc_tbl = HtmlTable.make;
    root.put(tc_tbl.root);
    tc_tbl.root.putAttr("class", "overlap_tbl");
    tc_tbl.putColumn("Test Case").putAttr("class", tableColumnHdrStyle);
    foreach (tc; report.testCases) {
        auto r = tc_tbl.newRow;
        r.td.put(tc.name);
    }
}
