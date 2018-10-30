/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_stats;

import std.conv : to;
import std.datetime : Clock, dur;
import std.format : format;
import std.typecons : tuple;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.html.nodes;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.type : MutationKind;

@safe:

auto makeStats(ref Database db, const(MutationKind)[] humanReadableKinds,
        const(Mutation.Kind)[] kinds) {
    auto statsh = defaultHtml(format("Mutation Testing Report %(%s %) %s",
            humanReadableKinds, Clock.currTime));
    auto s = statsh.preambleBody.n("style".Tag);
    s.putAttr("type", "text/css");
    s.put(
            `.stat_tbl {border-collapse:collapse; border-spacing: 0;border-style: solid;border-width:1px;}`);
    s.put(`.stat_tbl td{border-style: none;}`);
    s.put(`.overlap_tbl  {border-collapse:collapse;border-spacing:0;}`);
    s.put(`.overlap_tbl td{font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:black;}`);
    s.put(`.overlap_tbl th{font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:black;}`);
    s.put(`.overlap_tbl .tg-g59y{font-weight:bold;background-color:#ffce93;border-color:#000000;text-align:left;vertical-align:top}`);
    s.put(`.overlap_tbl .tg-0lax{text-align:left;vertical-align:top}`);
    s.put(
            `.overlap_tbl .tg-0lax_dark{background-color: lightgrey;text-align:left;vertical-align:top}`);

    overallStat(reportStatistics(db, kinds), statsh.body_);
    deadTestCase(reportDeadTestCases(db), statsh.body_);
    overlapTestCase(reportTestCaseFullOverlap(db, kinds), statsh.body_);

    return statsh;
}

private:

void overallStat(const MutationStat s, HtmlNode n) {
    n.n("h2".Tag).put("Summary");

    double score = 1.0;
    if (s.total > 0)
        score = cast(double) s.killed / cast(double) s.total;
    n.n("p".Tag).put(format("Mutation Score %s", score));

    if (s.untested > 0 && s.predictedDone > 0.dur!"msecs") {
        n.n("p".Tag).put(format("Predicted time until mutation testing is done %s (%s)",
                s.predictedDone, Clock.currTime + s.predictedDone));
    }

    n.n("p".Tag).put(format("Execution time %s", s.totalTime));

    auto tbl = HtmlTable.make;
    n.put(tbl.root);
    tbl.root.putAttr("class", "stat_tbl");
    tbl.putColumn("Status");
    tbl.putColumn("Count");

    foreach (const d; [tuple("Alive", s.alive), tuple("Killed", s.killed),
            tuple("Timeout", s.timeout), tuple("Total", s.total), tuple("Untested",
                s.untested), tuple("Killed by compiler", s.killedByCompiler)]) {
        auto r = tbl.newRow;
        r.td.put(d[0]);
        r.td.put(d[1].to!string);
    }
}

void deadTestCase(const TestCaseDeadStat s, HtmlNode n) {
    if (s.numDeadTC == 0)
        return;

    n.n("h2".Tag).put("Dead Test Cases");
    n.n("p".Tag).put("These test case have killed zero mutants. There is a high probability that these contain implementation errors. They should be manually inspected.");

    n.n("p".Tag).put(format("%s/%s = %s of all test cases", s.numDeadTC, s.total, s.ratio));

    auto tbl = HtmlTable.make;
    n.put(tbl.root);
    tbl.root.putAttr("class", "stat_tbl");
    tbl.putColumn("Test Case");
    foreach (tc; s.testCases) {
        tbl.newRow.td.put(tc.name);
    }
}

void overlapTestCase(const TestCaseOverlapStat s, HtmlNode n) {
    import std.algorithm : sort, map, filter, count;
    import std.array : array;
    import std.range : enumerate;

    if (s.total == 0)
        return;

    n.n("h2".Tag).put("Overlapping Test Cases");
    n.n("p".Tag).put("These test has killed exactly the same mutants. This is an indication that they verify the same aspects. This can mean that some of them may be redundant.");

    n.n("p".Tag).put(s.sumToString);

    auto tbl = HtmlTable.make;
    n.put(tbl.root);
    tbl.root.putAttr("class", "overlap_tbl");
    tbl.putColumn("Test Case").putAttr("class", "tg-g59y");
    tbl.putColumn("Count").putAttr("class", "tg-g59y");
    tbl.putColumn("Mutation IDs").putAttr("class", "tg-g59y");

    foreach (tcs; s.tc_mut.byKeyValue.filter!(a => a.value.length > 1).enumerate) {
        bool first = true;
        string cls = () {
            if (tcs.index % 2 == 0)
                return "tg-0lax";
            return "tg-0lax_dark";
        }();

        // TODO this is a bit slow. use a DB row iterator instead.
        foreach (name; tcs.value.value.map!(id => s.name_tc[id].idup).array.sort) {
            auto r = tbl.newRow;
            if (first) {
                r.td.put(name).putAttr("class", cls);
                r.td.put(s.mutid_mut[tcs.value.key].length.to!string).putAttr("class", cls);
                r.td.put(format("%(%s %)", s.mutid_mut[tcs.value.key])).putAttr("class", cls);
            } else {
                r.td.put(name).putAttr("class", cls);
            }
            first = false;
        }
    }
}
