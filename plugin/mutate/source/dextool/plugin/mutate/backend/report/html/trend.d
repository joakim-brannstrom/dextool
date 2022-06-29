/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.trend;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Element, Link;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : reportTrendByCodeChange,
    reportMutationScoreHistory, MutationScoreHistory;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.backend.report.html.utility : generatePopupHelp;

void makeTrend(ref Database db, string tag, Element root, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : SysTime;
    import dextool.plugin.mutate.backend.report.html.tmpl : TimeScalePointGraph;

    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Trend");

    auto base = root.addChild("div");

    auto ts = TimeScalePointGraph("ScoreHistory");

    const history = reportMutationScoreHistory(db).rollingAvg;
    if (history.data.length > 2 && history.estimate.x != SysTime.init) {
        foreach (v; history.data) {
            ts.put("Score", TimeScalePointGraph.Point(v.timeStamp, v.score.get));
        }
        ts.setColor("Score", "blue");

        ts.put("Trend", TimeScalePointGraph.Point(history.estimate.x, history.estimate.avg));
        ts.put("Trend", TimeScalePointGraph.Point(history.data[$ - 1].timeStamp,
                history.data[$ - 1].score.get));
        ts.put("Trend", TimeScalePointGraph.Point(history.estimate.predX,
                history.estimate.predScore));
        ts.setColor("Trend", () {
            final switch (history.estimate.trend) with (MutationScoreHistory.Trend) {
            case undecided:
                return "grey";
            case negative:
                return "red";
            case positive:
                return "green";
            }
        }());

        ts.html(base, TimeScalePointGraph.Width(80));
        base.addChild("p")
            .appendHtml(
                    "<i>trend</i> is a prediction of how the mutation score will change based on previous scores.");
    }

    const codeChange = reportTrendByCodeChange(db, kinds);
    if (codeChange.sample.length > 2) {
        ts = TimeScalePointGraph("ScoreByCodeChange");
        foreach (v; codeChange.sample) {
            ts.put("Score", TimeScalePointGraph.Point(v.timeStamp, v.value.get));
        }
        ts.setColor("Score", "purple");
        ts.html(base, TimeScalePointGraph.Width(80));
        
        auto info = base.addChild("div", "Code change");
        generatePopupHelp(info, "Code change is a prediction of how the mutation score will change based on the latest code changes.");
    }
}
