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
    reportMutationScoreHistory, MutationScoreHistory;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.type : Mutation;

void makeTrend(ref Database db, string tag, Element root, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : SysTime;
    import dextool.plugin.mutate.backend.report.html.tmpl : TimeScalePointGraph;

    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Trend");

    auto base = root.addChild("div");

    auto ts = TimeScalePointGraph("ScoreHistory");

    const history = reportMutationScoreHistory(db);
    string color;
    int colorValue;
    auto rng = new Random(unpredictableSeed);
    double score;

    if (history.data.length > 1){
      foreach(value; history.data){
        color = "#";
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
        score = rint(value.score.get * 1000)/1000;

        ts.put(value.filePath, TimeScalePointGraph.Point(value.timeStamp, score));
        ts.setColor(value.filePath, color, color);
      }
    }

    ts.html(base, TimeScalePointGraph.Width(80));
        base.addChild("p")
            .appendHtml(
                    "<i>trend</i> is a graph displaying how the MutationScore has changed between tests.");

}
