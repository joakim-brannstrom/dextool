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

import arsd.dom : Document, Element, require, Table;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

string makeStats(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import dextool.plugin.mutate.type : ReportSection;
    import dextool.set;

    auto sections = setFromList(conf.reportSection);

    auto doc = tmplBasicPage;
    doc.title(format("Mutation Testing Report %(%s %) %s", humanReadableKinds, Clock.currTime));

    overallStat(reportStatistics(db, kinds), doc.mainBody);
    if (ReportSection.tc_killed_no_mutants in sections)
        deadTestCase(reportDeadTestCases(db), doc.mainBody);
    if (ReportSection.tc_full_overlap in sections
            || ReportSection.tc_full_overlap_with_mutation_id in sections)
        overlapTestCase(reportTestCaseFullOverlap(db, kinds), doc.mainBody);

    return doc.toPrettyString;
}

private:

void overallStat(const MutationStat s, Element n) {
    import std.conv : to;
    import std.typecons : tuple;

    n.addChild("h2", "Summary");
    n.addChild("p").appendHtml(format("Mutation Score <b>%.3s</b>", s.score));
    n.addChild("p", format("Execution time %s", s.totalTime));

    if (s.untested > 0 && s.predictedDone > 0.dur!"msecs") {
        n.addChild("p", format("Predicted time until mutation testing is done %s (%s)",
                s.predictedDone, Clock.currTime + s.predictedDone));
    }

    auto tbl = tmplDefaultTable(n, ["Type", "Value"]);
    foreach (const d; [tuple("Alive", s.alive), tuple("Killed", s.killed),
            tuple("Timeout", s.timeout), tuple("Total", s.total), tuple("Untested",
                s.untested), tuple("Killed by compiler", s.killedByCompiler),]) {
        tbl.appendRow(d[0], d[1]);
    }

    if (s.aliveNoMut != 0) {
        tbl.appendRow("Suppressed (nomut)", s.aliveNoMut.to!string);
        tbl.appendRow("Suppressed/total", s.suppressedOfTotal.to!string);

        n.addChild("p", "Suppressed is the number of mutants that are alive but ignored. ")
            .appendText("This result in those mutants positivly affecting the mutation score. ")
            .appendText("The suppressed/total is how much it has influeced the mutation score. ")
            .appendHtml("You <b>should</b> react if it is too high.");
    }
}

void deadTestCase(const TestCaseDeadStat s, Element n) {
    if (s.numDeadTC == 0)
        return;

    n.addChild("h2", "Dead Test Cases");
    n.addChild("p", "These test case have killed zero mutants. There is a high probability that these contain implementation errors. They should be manually inspected.");

    n.addChild("p", format("%s/%s = %s of all test cases", s.numDeadTC, s.total, s.ratio));

    auto tbl = tmplDefaultTable(n, ["Test Case"]);
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

    n.addChild("h2", "Overlapping Test Cases");
    n.addChild("p", "These test has killed exactly the same mutants. This is an indication that they verify the same aspects. This can mean that some of them may be redundant.");

    n.addChild("p", s.sumToString);

    auto tbl = tmplDefaultTable(n, ["Test Case", "Count", "Mutation IDs"]);

    foreach (tcs; s.tc_mut.byKeyValue.filter!(a => a.value.length > 1).enumerate) {
        bool first = true;
        string cls = () {
            if (tcs.index % 2 == 0)
                return tableRowStyle;
            return tableRowDarkStyle;
        }();

        // TODO this is a bit slow. use a DB row iterator instead.
        foreach (name; tcs.value.value.map!(id => s.name_tc[id].idup).array.sort) {
            auto r = tbl.addChild("tr");
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
