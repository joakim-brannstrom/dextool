/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_dead_test_case;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : TestCaseDeadStat, reportDeadTestCases;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

auto makeDeadTestCase(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;
    doc.title(format("Killed No Mutants Test Cases %(%s %) %s",
            humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, js_index));

    toHtml(reportDeadTestCases(db), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(const TestCaseDeadStat s, Element n) {
    if (s.numDeadTC == 0)
        return;
    auto base = n.addChild("div").addClass("base");
    auto heading = base.addChild("h1").addClass("tbl_header");
    heading.addChild("i").addClass("right");
    heading.appendText(" Killed No Mutants Test Cases");

    base.addChild("p", "These test case have killed zero mutants. There is a high probability that these contain implementation errors. They should be manually inspected.");

    base.addChild("p", format("%s/%s = %s of all test cases", s.numDeadTC, s.total, s.ratio));
    auto tbl_container = base.addChild("div").addClass("tbl_container");
    auto tbl = tmplDefaultTable(tbl_container, ["Test Case"]);
    foreach (tc; s.testCases) {
        tbl.appendRow(tc.name);
    }
}
