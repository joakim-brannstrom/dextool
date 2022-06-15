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
import std.container : DList;

import arsd.dom : Element, Link;
import my.path : AbsolutePath;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MutationStat,
    reportStatistics, reportSyncStatus, SyncStatus;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplDefaultTable,
    PieGraph, TimeScalePointGraph;
import dextool.plugin.mutate.backend.type : Mutation;

void makeStats(ref Database db, string tag, Element root,
        const(Mutation.Kind)[] kinds, const AbsolutePath workListFname) @trusted {
    import dextool.plugin.mutate.backend.report.html.page_worklist;
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Overview");
    string[] files = db.getFilesStrings;
    overallStat(reportStatistics(db, kinds, files), root.addChild("div"));
    makeWorklistPage(db, root, workListFname);
    syncStatus(reportSyncStatus(db, kinds, 100), root);
}

private:

// TODO: this function contains duplicated logic from the one in ../utility.d
void overallStat(MutationStat[] statList, Element base) {
    import std.conv : to;
    import std.typecons : tuple;
    import core.time : Duration;

    MutationStat s;
    Duration predictedDone;

    foreach(statVal; statList){
      s.untested += statVal.untested;
      s.killedByCompiler += statVal.killedByCompiler;
      s.worklist += statVal.worklist;
      s.totalTime.compile += statVal.totalTime.compile;
      s.totalTime.test += statVal.totalTime.test;

      s.scoreData.alive += statVal.scoreData.alive;
      s.scoreData.killed += statVal.scoreData.killed;
      s.scoreData.timeout += statVal.scoreData.timeout;
      s.scoreData.total += statVal.scoreData.total;
      s.scoreData.noCoverage += statVal.scoreData.noCoverage;
      s.scoreData.equivalent += statVal.scoreData.equivalent;
      s.scoreData.skipped += statVal.scoreData.skipped;
      s.scoreData.memOverload += statVal.scoreData.memOverload;
      s.scoreData.totalTime.compile += statVal.scoreData.totalTime.compile;
      s.scoreData.totalTime.test += statVal.scoreData.totalTime.test;
      s.scoreData.aliveNoMut += statVal.scoreData.aliveNoMut;
      predictedDone += statVal.predictedDone;
    }

    base.addChild("p").appendHtml(format("Mutation Score <b>%.3s</b>", s.score()));
    base.addChild("p", format("Time spent: %s", s.totalTime));

    if (s.untested > 0 && s.predictedDone > 0.dur!"msecs") {
        const pred = Clock.currTime + predictedDone;
        base.addChild("p", format("Remaining: %s (%s)", predictedDone, pred.toISOExtString));
    }

    PieGraph("score", [
            PieGraph.Item("alive", "red", s.alive - s.aliveNoMut),
            PieGraph.Item("killed", "green", s.killed),
            PieGraph.Item("Untested", "grey", s.untested),
            PieGraph.Item("Timeout", "lightgreen", s.timeout)
            ]).html(base, PieGraph.Width(50));

    auto tbl = tmplDefaultTable(base, ["Type", "Value"]);
    foreach (const d; [
            tuple("Total", s.total),
            tuple("Killed by compiler", cast(long) s.killedByCompiler),
            tuple("Skipped", s.skipped), tuple("Equivalent", s.equivalent),
            tuple("Worklist", cast(long) s.worklist),
        ]) {
        tbl.appendRow(d[0], d[1]);
    }

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

void syncStatus(SyncStatus status, Element root) {
    auto ts = TimeScalePointGraph("SyncStatus");

    ts.put("Test", TimeScalePointGraph.Point(status.test, 1.6));
    ts.setColor("Test", "lightBlue", "lightBlue");

    ts.put("Code", TimeScalePointGraph.Point(status.code, 1.4));
    ts.setColor("Code", "lightGreen", "lightGreen");

    ts.put("Coverage", TimeScalePointGraph.Point(status.coverage, 1.2));
    ts.setColor("Coverage", "purple", "purple");

    if (status.mutants.length != 0) {
        double y = 0.8;
        foreach (v; status.mutants) {
            ts.put("Mutant", TimeScalePointGraph.Point(v.updated, y));
            y += 0.3 / status.mutants.length;
        }
        ts.setColor("Mutant", "red", "red");
    }
    ts.html(root, TimeScalePointGraph.Width(50));

    root.addChild("p").appendHtml("<i>sync status</i> is how old the information about mutants and their status is compared to when the tests or source code where last changed");
}
