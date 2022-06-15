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

void makeTrend(ref Database db, string tag, Element root, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : SysTime;
    import dextool.plugin.mutate.backend.report.html.tmpl : TimeScalePointGraph;

    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Trend");

    auto base = root.addChild("div");

    const history = reportMutationScoreHistory(db);

    foreach(data; history.data){
      base.addChild("p", format("%s (%s): %s", data.filePath, data.timeStamp, data.score.get));
    }
}
