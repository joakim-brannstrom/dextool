/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_test_case_full_overlap;

import logger = std.experimental.logger;
import std.datetime : Clock, dur;
import std.format : format;

import arsd.dom : Element, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : TestCaseOverlapStat,
    reportTestCaseFullOverlap;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    tmplDefaultTable, dashboardCss;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

string makeFullOverlapTestCase(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import dextool.plugin.mutate.type : ReportSection;
    import my.set;

    auto sections = conf.reportSection.toSet;

    auto doc = tmplBasicPage.dashboardCss;
    doc.title(format("Full Overlap Test Cases %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, jsIndex));

    toHtml(reportTestCaseFullOverlap(db, kinds), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(const TestCaseOverlapStat s, Element n) {
    import std.algorithm : sort, map, filter;
    import std.array : array;
    import std.conv : to;
    import std.range : enumerate;

    if (s.total == 0)
        return;

    auto base = n.addChild("div").addClass("base");
    auto heading = base.addChild("h1").addClass("tbl_header");
    heading.addChild("i").addClass("right");
    heading.appendText(" Overlapping Test Cases");

    base.addChild("p", "These test has killed exactly the same mutants. This is an indication that they verify the same aspects. This can mean that some of them may be redundant.");

    base.addChild("p", s.sumToString);

    auto tbl_container = base.addChild("div").addClass("tbl_container");

    auto tbl = tmplDefaultTable(tbl_container, [
            "Test Case", "Count", "Mutation IDs"
            ]);

    foreach (tcs; s.tc_mut.byKeyValue.filter!(a => a.value.length > 1).enumerate) {
        bool first = true;
        string cls = () {
            if (tcs.index % 2 == 0)
                return Table.rowStyle;
            return Table.rowDarkStyle;
        }();

        // TODO this is a bit slow. use a DB row iterator instead.
        foreach (name; tcs.value.value.map!(id => s.name_tc[id].idup).array.sort) {
            auto r = tbl.appendRow();
            if (first) {
                r.addChild("td", name).addClass(cls);
                r.addChild("td", s.mutid_mut[tcs.value.key].length.to!string).addClass(cls);
                r.addChild("td", format("%(%s %)", s.mutid_mut[tcs.value.key])).addClass(cls);
            } else {
                r.addChild("td", name).addClass(cls);
            }
            first = false;
        }
    }
}
