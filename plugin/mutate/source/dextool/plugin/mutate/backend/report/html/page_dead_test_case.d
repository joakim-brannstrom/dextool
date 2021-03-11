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

import arsd.dom : Document, Element, require, Table, RawSource, Link;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : TestCaseDeadStat, reportDeadTestCases;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    dashboardCss, tmplDefaultTable;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

void makeDeadTestCase(ref Database db, const(Mutation.Kind)[] kinds, string tag, Element root) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id",
            tag[1 .. $]), "Killed No Mutants Test Cases");
    toHtml(reportDeadTestCases(db), root);
}

private:

void toHtml(const TestCaseDeadStat s, Element n) {
    if (s.numDeadTC == 0)
        return;

    auto base = n.addChild("div").addClass("base");
    base.addChild("p", "These test case have killed zero mutants. There is a high probability that these contain implementation errors. They should be manually inspected.");

    base.addChild("p", format("%s/%s = %s of all test cases", s.numDeadTC, s.total, s.ratio));
    auto tbl_container = base.addChild("div").addClass("tbl_container");
    auto tbl = tmplDefaultTable(tbl_container, ["Test Case"]);
    foreach (tc; s.testCases) {
        tbl.appendRow(tc.name);
    }
}
