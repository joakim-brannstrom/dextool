/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_test_groups;

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

auto makeTestGroups(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) {
    import dextool.plugin.mutate.backend.report.html.tmpl : addStateTableCss;

    auto root = defaultHtml(format("Long Term View %(%s %) %s", humanReadableKinds, Clock.currTime));
    auto s = root.preambleBody.n("style".Tag);
    addStateTableCss(s);

    if (conf.testGroups.length != 0)
        root.body_.n("h2".Tag).put("Test Groups");
    foreach (tg; conf.testGroups)
        testGroups(reportTestGroups(db, kinds, tg), root.body_);

    return root;
}

private:

void testGroups(const TestGroupStat test_g, HtmlNode n) {
    import std.array : array;
    import std.path : buildPath;
    import std.range : enumerate;
    import dextool.plugin.mutate.backend.mutation_type : toUser;

    n.n("h3".Tag).put(test_g.description);

    auto stat_tbl = HtmlTable.make;
    n.put(stat_tbl.root);
    stat_tbl.root.putAttr("class", "overlap_tbl");
    foreach (const d; [tuple("Mutation Score", test_g.stats.score.to!string),
            tuple("Alive", test_g.stats.alive.to!string), tuple("Total",
                test_g.stats.total.to!string)]) {
        auto r = stat_tbl.newRow;
        r.td.put(d[0]);
        r.td.put(d[1]);
    }

    with (n.n("p".Tag)) {
        put("Mutation data per file.");
        put("The killed mutants are those that where killed by this test group.");
        put("Therefor the total here is less than the reported total.");
    }
    auto file_tbl = HtmlTable.make;
    n.put(file_tbl.root);
    file_tbl.root.putAttr("class", "overlap_tbl");
    foreach (c; ["File", "Alive", "Killed"])
        file_tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);

    foreach (const pkv; test_g.files
            .byKeyValue
            .map!(a => tuple(a.key, a.value.dup))
            .array
            .sort!((a, b) => a[1] < b[1])) {
        auto r = file_tbl.newRow;
        const path = test_g.files[pkv[0]];
        r.td.put(path);

        auto alive_ids = r.td;
        if (auto alive = pkv[0] in test_g.alive) {
            foreach (a; (*alive).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                alive_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                        format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                alive_ids.put(" ");
            }
        }

        auto killed_ids = r.td;
        if (auto killed = pkv[0] in test_g.killed) {
            foreach (a; (*killed).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                killed_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                        format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                killed_ids.put(" ");
            }
        }
    }

    auto tc_tbl = HtmlTable.make;
    n.put(tc_tbl.root);
    tc_tbl.root.putAttr("class", "overlap_tbl");
    tc_tbl.putColumn("Test Case").putAttr("class", tableColumnHdrStyle);
    foreach (tc; test_g.testCases) {
        auto r = tc_tbl.newRow;
        r.td.put(tc.name);
    }
}
