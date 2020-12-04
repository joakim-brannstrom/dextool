/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_stats;

import logger = std.experimental.logger;
import std.datetime : Clock, dur;
import std.format : format;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MutationStat, TestCaseDeadStat,
    TestCaseOverlapStat, reportStatistics, reportDeadTestCases, reportTestCaseFullOverlap;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

string makeStats(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import dextool.plugin.mutate.type : ReportSection;
    import my.set;

    auto sections = conf.reportSection.toSet;

    auto doc = tmplBasicPage;

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, js_similarity));

    doc.title(format("Mutation Testing Report %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");
    overallStat(reportStatistics(db, kinds), doc.mainBody);
    if (ReportSection.tc_killed_no_mutants in sections)
        deadTestCase(reportDeadTestCases(db), doc.mainBody);
    if (ReportSection.tc_full_overlap in sections
            || ReportSection.tc_full_overlap_with_mutation_id in sections)
        overlapTestCase(reportTestCaseFullOverlap(db, kinds), doc.mainBody);

    return doc.toPrettyString;
}

private:

// TODO: this function contains duplicated logic from the one in ../utility.d
void overallStat(const MutationStat s, Element n) {
    import std.conv : to;
    import std.typecons : tuple;

    n.addChild("p",
            "The tables are hidden by default, click on the corresponding header to display a table.");
    with (n.addChild("button", "expand all")) {
        setAttribute("type", "button");
        setAttribute("id", "expand_all");
    }
    with (n.addChild("button", "collapse all")) {
        setAttribute("type", "button");
        setAttribute("id", "collapse_all");
    }

    auto comp_container = n.addChild("div").addClass("comp_container");
    auto heading = comp_container.addChild("h2").addClass("tbl_header");

    comp_container.addChild("p").appendHtml(format("Mutation Score <b>%.3s</b> (trend %.3s)",
            s.score, s.estimate.value.get));
    comp_container.addChild("p", format("Time spent: %s", s.totalTime));
    heading.addChild("i").addClass("right");
    heading.appendText(" Summary");
    if (s.untested > 0 && s.predictedDone > 0.dur!"msecs") {
        const pred = Clock.currTime + s.predictedDone;
        comp_container.addChild("p", format("Remaining: %s (%s)",
                s.predictedDone, pred.toISOExtString));
    }

    auto tbl_container = comp_container.addChild("div").addClass("tbl_container");
    tbl_container.setAttribute("style", "display: none;");
    auto tbl = tmplDefaultTable(tbl_container, ["Type", "Value"]);
    foreach (const d; [
            tuple("Total", s.total), tuple("Untested", s.untested),
            tuple("Alive", s.alive), tuple("Killed", s.killed),
            tuple("Timeout", s.timeout),
            tuple("Killed by compiler", s.killedByCompiler),
            tuple("Worklist", s.worklist),
        ]) {
        tbl.appendRow(d[0], d[1]);
    }

    comp_container.addChild("p").appendHtml(
            "<i>trend</i> is a prediction of how the mutation score will based on the latest code changes.");
    comp_container.addChild("p").appendHtml(
            "<i>worklist</i> is the number of mutants that are in the queue to be tested/retested.");

    if (s.aliveNoMut != 0) {
        tbl.appendRow("NoMut", s.aliveNoMut.to!string);
        tbl.appendRow("NoMut/total", format("%.3s", s.suppressedOfTotal));

        auto p = comp_container.addChild("p",
                "NoMut is the number of mutants that are alive but ignored.");
        p.appendHtml(" They are <i>suppressed</i>.");
        p.appendText(" This result in those mutants increasing the mutation score.");
        p.appendText(" The suppressed/total is how much it has increased.");
        p.appendHtml(" You <b>should</b> react if it is high.");
    }
}

void deadTestCase(const TestCaseDeadStat s, Element n) {
    if (s.numDeadTC == 0)
        return;
    auto comp_container = n.addChild("div").addClass("comp_container");
    auto heading = comp_container.addChild("h2").addClass("tbl_header");
    heading.addChild("i").addClass("right");
    heading.appendText(" Dead Test Cases");

    comp_container.addChild("p", "These test case have killed zero mutants. There is a high probability that these contain implementation errors. They should be manually inspected.");

    comp_container.addChild("p", format("%s/%s = %s of all test cases",
            s.numDeadTC, s.total, s.ratio));
    auto tbl_container = comp_container.addChild("div").addClass("tbl_container");
    tbl_container.setAttribute("style", "display: none;");
    auto tbl = tmplDefaultTable(tbl_container, ["Test Case"]);
    foreach (tc; s.testCases) {
        tbl.appendRow(tc.name);
    }
}

void overlapTestCase(const TestCaseOverlapStat s, Element n) {
    import std.algorithm : sort, map, filter;
    import std.array : array;
    import std.conv : to;
    import std.range : enumerate;

    if (s.total == 0)
        return;
    auto comp_container = n.addChild("div").addClass("comp_container");
    auto heading = comp_container.addChild("h2").addClass("tbl_header");
    heading.addChild("i").addClass("right");
    heading.appendText(" Overlapping Test Cases");

    comp_container.addChild("p", "These test has killed exactly the same mutants. This is an indication that they verify the same aspects. This can mean that some of them may be redundant.");

    comp_container.addChild("p", s.sumToString);

    auto tbl_container = comp_container.addChild("div").addClass("tbl_container");

    tbl_container.setAttribute("style", "display: none;");
    auto tbl = tmplDefaultTable(tbl_container, [
            "Test Case", "Count", "Mutation IDs"
            ]);

    foreach (tcs; s.tc_mut.byKeyValue.filter!(a => a.value.length > 1).enumerate) {
        bool first = true;
        string cls = () {
            if (tcs.index % 2 == 0)
                return tableRowStyle;
            return tableRowDarkStyle;
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
