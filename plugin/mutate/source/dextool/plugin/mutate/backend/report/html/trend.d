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
import std.random;
import std.conv;
import std.math;

import arsd.dom : Element, Link;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : reportTrendByCodeChange,
    reportMutationScoreHistory, reportMutationScoreHistoryByFile, MutationScoreHistory;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.type : Mutation;

import std.datetime : SysTime;
import dextool.plugin.mutate.backend.report.html.tmpl : TimeScalePointGraph;

string randomColorHex(){
    auto rng = Random(unpredictableSeed);
    int colorValue;
    string color = "#";
    for(int i = 0; i < 6; i++){
      colorValue = uniform(0, 15, rng);
      if(colorValue < 10){
        color ~= to!string(colorValue);
      }else{
        switch(colorValue){
          case 10: color ~= "a";
            break;
          case 11: color ~= "b";
            break;
          case 12: color ~= "c";
            break;
          case 13: color ~= "d";
            break;
          case 14: color ~= "e";
            break;
          case 15: color ~= "f";
            break;
          default:
            break;
        }
      }
    }
    return color;
}

void makeTrend(ref Database db, string tag, Element root, const(Mutation.Kind)[] kinds) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Trend");

    auto base = root.addChild("div");

    auto ts = TimeScalePointGraph("ScoreHistory");

    const history = reportMutationScoreHistory(db).rollingAvg;
    if (history.data.length > 2 && history.estimate.x != SysTime.init) {
        foreach (v; history.data) {
            ts.put("Score", TimeScalePointGraph.Point(v.timeStamp, v.score.get));
        }
        ts.setColor("Score", "blue", "blue");

        ts.put("Trend", TimeScalePointGraph.Point(history.estimate.x, history.estimate.avg));
        ts.put("Trend", TimeScalePointGraph.Point(history.data[$ - 1].timeStamp,
                history.data[$ - 1].score.get));
        ts.put("Trend", TimeScalePointGraph.Point(history.estimate.predX,
                history.estimate.predScore));

        string color = () {
            final switch (history.estimate.trend) with (MutationScoreHistory.Trend) {
            case undecided:
                return "grey";
            case negative:
                return "red";
            case positive:
                return "green";
            }
        }();
        ts.setColor("Trend", color, color);

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
        ts.setColor("Score", "purple", "purple");
        ts.html(base, TimeScalePointGraph.Width(80));
        base.addChild("p").appendHtml(
                "<i>code change</i> is a prediction of how the mutation score will change based on the latest code changes.");
    }
}

void makeFileTrend(ref Database db, string tag, Element root, const(Mutation.Kind)[] kinds) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Trend by file");

    string[string] lineColor;
    auto base = root.addChild("div");
    auto ts = TimeScalePointGraph("ScoreHistory");
    
    const history = reportMutationScoreHistoryByFile(db);
    double score;
    string color;

    //Add all the score histories to the graph
    if (history.data.length > 1){
      foreach(value; history.data){
        color = randomColorHex();
        score = rint(value.score.get * 1000)/1000;
        lineColor[value.filePath] = color;
        ts.put(value.filePath, TimeScalePointGraph.Point(value.timeStamp, score));
        ts.setColor(value.filePath, color, color);
      }
    }

    ts.html(base, TimeScalePointGraph.Width(80));
        base.addChild("p")
            .appendHtml(
                    "<i>trend by file</i> is a graph displaying how the MutationScore has changed between tests.");
}
