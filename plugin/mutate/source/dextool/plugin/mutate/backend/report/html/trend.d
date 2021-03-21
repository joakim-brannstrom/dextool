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
    reportMutationScoreHistory;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.type : Mutation;

void makeTrend(ref Database db, const(Mutation.Kind)[] kinds, string tag, Element root) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Trend");

    auto base = root.addChild("div");

    const history = reportMutationScoreHistory(db);
    base.addChild("p").appendHtml(format("History %.3s", history.estimate.get));
    const codeChange = reportTrendByCodeChange(db, kinds);
    base.addChild("p").appendHtml(format("Code change %.3s", codeChange.value.get));

    base.addChild("p").appendHtml(
            "<i>history</i> is a prediction of how the mutation score will change based on previous scores.");
    base.addChild("p").appendHtml(
            "<i>code change</i> is a prediction of how the mutation score will change based on the latest code changes.");
}
