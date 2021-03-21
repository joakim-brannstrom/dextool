/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
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

import arsd.dom : Element, Table, RawSource, Link;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MutationStat, reportStatistics;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplDefaultTable, PieGraph;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

void makeStats(ref Database db, const(Mutation.Kind)[] kinds, string tag, Element root) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Overview");
    overallStat(reportStatistics(db, kinds), root);
}

private:

// TODO: this function contains duplicated logic from the one in ../utility.d
void overallStat(const MutationStat s, Element n) {
    import std.conv : to;
    import std.typecons : tuple;

    auto base = n.addChild("div").addClass("base");

    base.addChild("p").appendHtml(format("Mutation Score <b>%.3s</b> (trend %.3s)",
            s.score, s.trendByCodeChange.value.get));
    base.addChild("p", format("Time spent: %s", s.totalTime));
    if (s.untested > 0 && s.predictedDone > 0.dur!"msecs") {
        const pred = Clock.currTime + s.predictedDone;
        base.addChild("p", format("Remaining: %s (%s)", s.predictedDone, pred.toISOExtString));
    }

    PieGraph("score", [
            PieGraph.Item("alive", "red", s.alive),
            PieGraph.Item("killed", "green", s.killed),
            PieGraph.Item("Untested", "grey", s.untested),
            PieGraph.Item("Timeout", "lightgreen", s.timeout)
            ]).html(base, PieGraph.Width(50));

    auto tbl = tmplDefaultTable(base, ["Type", "Value"]);
    foreach (const d; [
            tuple("Total", s.total),
            tuple("Killed by compiler", cast(long) s.killedByCompiler),
            tuple("Worklist", cast(long) s.worklist),
        ]) {
        tbl.appendRow(d[0], d[1]);
    }

    base.addChild("p").appendHtml(
            "<i>trend</i> is a prediction of how the mutation score will based on the latest code changes.");
    base.addChild("p").appendHtml(
            "<i>worklist</i> is the number of mutants that are in the queue to be tested/retested.");

    if (s.aliveNoMut != 0) {
        tbl.appendRow("NoMut", s.aliveNoMut.to!string);
        tbl.appendRow("NoMut/total", format("%.3s", s.suppressedOfTotal));

        auto p = base.addChild("p", "NoMut is the number of mutants that are alive but ignored.");
        p.appendHtml(" They are <i>suppressed</i>.");
        p.appendText(" This result in those mutants increasing the mutation score.");
        p.appendText(" The suppressed/total is how much it has increased.");
        p.appendHtml(" You <b>should</b> react if it is high.");
    }
}
