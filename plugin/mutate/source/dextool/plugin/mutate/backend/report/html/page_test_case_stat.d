/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_test_case_stat;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : reportTestCaseStats, TestCaseStat;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

auto makeTestCaseStats(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;
    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, js_index));
    doc.mainBody.setAttribute("onload", "init()");
    doc.title(format("Test Case Statistics %(%s %) %s", humanReadableKinds, Clock.currTime));

    toHtml(reportTestCaseStats(db, kinds), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(TestCaseStat stat, Element root) {
    import std.conv : to;
    import std.format : format;

    root.addChild("h2", "Test Case Statistics");
    root.addChild("p", "The test cases sorted by how many mutants they have killed. It can be used to e.g. find too sensitive test cases or those that are particularly ineffective (kills few mutants).");

    auto tbl_container = root.addChild("div").addClass("tbl_container");
    auto tbl = tmplDefaultTable(tbl_container, ["Ratio", "Kills", "Name"]);

    foreach (const v; stat.toSortedRange) {
        auto r = tbl.appendRow();
        r.addChild("td", format!"%.2f"(v.ratio));
        r.addChild("td", v.info.killedMutants.to!string);
        r.addChild("td", v.tc.name);
    }
}
