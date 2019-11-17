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
import std.format : format;

import arsd.dom : Document, Element, require, Table;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.report.analyzers : TestGroupStat, reportTestGroups;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

auto makeTestGroups(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;
    doc.title(format("Test Groups %(%s %) %s", humanReadableKinds, Clock.currTime));

    if (conf.testGroups.length != 0)
        doc.mainBody.addChild("h2", "Test Groups");
    foreach (tg; conf.testGroups)
        testGroups(reportTestGroups(db, kinds, tg), doc.mainBody);

    return doc.toPrettyString;
}

private:

void testGroups(const TestGroupStat test_g, Element root) {
    import std.algorithm : sort, map;
    import std.array : array;
    import std.conv : to;
    import std.path : buildPath;
    import std.typecons : tuple;
    import dextool.plugin.mutate.backend.mutation_type : toUser;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;

    root.addChild("h3", test_g.description);

    auto stat_tbl = tmplDefaultTable(root, ["Property", "Value"]);
    foreach (const d; [
            tuple("Mutation Score", test_g.stats.score.to!string),
            tuple("Alive", test_g.stats.alive.to!string),
            tuple("Total", test_g.stats.total.to!string)
        ]) {
        auto r = stat_tbl.appendRow();
        r.addChild("td", d[0]);
        r.addChild("td", d[1]);
    }

    with (root.addChild("p")) {
        appendText("Mutation data per file.");
        appendText("The killed mutants are those that where killed by this test group.");
        appendText("Therefor the total here is less than the reported total.");
    }

    auto file_tbl = tmplDefaultTable(root, ["File", "Alive", "Killed"]);

    foreach (const pkv; test_g.files
            .byKeyValue
            .map!(a => tuple(a.key, a.value.dup))
            .array
            .sort!((a, b) => a[1] < b[1])) {
        auto r = file_tbl.appendRow();

        const path = test_g.files[pkv[0]];
        r.addChild("td", path);

        auto alive_ids = r.addChild("td").setAttribute("valign", "top");
        if (auto alive = pkv[0] in test_g.alive) {
            foreach (a; (*alive).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                auto link = alive_ids.addChild("a", format("%s:%s", a.kind.toUser, a.sloc.line));
                link.href = format("%s#%s", buildPath(htmlFileDir, pathToHtmlLink(path)), a.id);
                alive_ids.appendText(" ");
            }
        }

        auto killed_ids = r.addChild("td").setAttribute("valign", "top");
        if (auto killed = pkv[0] in test_g.killed) {
            foreach (a; (*killed).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                auto link = killed_ids.addChild("a", format("%s:%s", a.kind.toUser, a.sloc.line));
                link.href = format("%s#%s", buildPath(htmlFileDir, pathToHtmlLink(path)), a.id);
                killed_ids.appendText(" ");
            }
        }
    }

    auto tc_tbl = tmplDefaultTable(root, ["Test Case"]);
    foreach (tc; test_g.testCases) {
        tc_tbl.appendRow(tc.name);
    }
}
