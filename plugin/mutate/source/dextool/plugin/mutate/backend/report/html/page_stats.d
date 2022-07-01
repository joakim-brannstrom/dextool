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

import arsd.dom : Element, Link;
import my.path : AbsolutePath;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MutationStat,
    reportStatistics, reportSyncStatus, SyncStatus;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplDefaultTable,
    PieGraph, TimeScalePointGraph;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.backend.report.html.utility;

void makeStats(ref Database db, string tag, Element root,
        const(Mutation.Kind)[] kinds, const AbsolutePath workListFname) @trusted {
    import dextool.plugin.mutate.backend.report.html.page_worklist;

    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Overview");
    overallStat(reportStatistics(db, kinds), root.addChild("div"));
    makeWorklistPage(db, root, workListFname);
    syncStatus(reportSyncStatus(db, kinds, 100), root);
}

private:

// TODO: this function contains duplicated logic from the one in ../utility.d
void overallStat(const MutationStat s, Element base) {
    import std.conv : to;
    import std.typecons : tuple;

    base.addChild("p").appendHtml(format("Mutation Score <b>%.3s</b>", s.score));
    auto time = base.addChild("div", "Time spent"); 
    generatePopupHelp(time, format("%s", s.totalTime));
    
    if (s.untested > 0 && s.predictedDone > 0.dur!"msecs") {
        const pred = Clock.currTime + s.predictedDone;
        base.addChild("p", format("Remaining: %s (%s)", s.predictedDone, pred.toISOExtString));
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
        ]) {
        tbl.appendRow(d[0], d[1]);
    }
    {
        auto wlRow = tbl.appendRow;
        auto wltd = wlRow.addChild("td");
        wltd.addChild("a", "Worklist").setAttribute("href", "worklist.html");
        generatePopupHelp(wltd, "Worklist is the number of mutants that are in the same queue to be tested/retested");
        wltd.addChild("td", s.worklist.to!string);
    }

    if (s.aliveNoMut != 0) {
        auto nmRow = tbl.appendRow;
        auto nmtd = nmRow.addChild("td", "NoMut");
        generatePopupHelp(nmtd, "NoMut is the number of mutants that are alive but ignored. 
            They are suppressed. 
            This result in those mutants increasing the mutation score.");
        nmtd.addChild("td", s.aliveNoMut.to!string);

        auto nmtotalRow = tbl.appendRow;
        auto nmtotaltd = nmtotalRow.addChild("td", "NoMut/total");
        generatePopupHelp(nmtotaltd, "NoMut/total (Supressed/total) is how much the result has increased.
            You should react if it is high.");
        nmtotaltd.addChild("td", format("%.3s", s.suppressedOfTotal));
    }
}

void syncStatus(SyncStatus status, Element root) {
    auto ts = TimeScalePointGraph("SyncStatus");

    ts.put("Test", TimeScalePointGraph.Point(status.test, 1.6));
    ts.setColor("Test", "lightBlue");

    ts.put("Code", TimeScalePointGraph.Point(status.code, 1.4));
    ts.setColor("Code", "lightGreen");

    ts.put("Coverage", TimeScalePointGraph.Point(status.coverage, 1.2));
    ts.setColor("Coverage", "purple");

    if (status.mutants.length != 0) {
        double y = 0.8;
        foreach (v; status.mutants) {
            ts.put("Mutant", TimeScalePointGraph.Point(v.updated, y));
            y += 0.3 / status.mutants.length;
        }
        ts.setColor("Mutant", "red");
    }
    ts.html(root, TimeScalePointGraph.Width(50));

    auto info = root.addChild("div", "Sync Status");
    generatePopupHelp(info, "Sync Status is how old the information about mutants and their status is compared to when the tests or source code where last changed.");

}
