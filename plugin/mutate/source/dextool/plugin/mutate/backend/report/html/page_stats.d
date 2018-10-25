/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_stats;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.type : MutationKind;
import dextool.plugin.mutate.backend.type : Mutation;

@safe:

auto makeStats(ref Database db, const(MutationKind)[] humanReadableKinds,
        const(Mutation.Kind)[] kinds) {
    import std.datetime : Clock;
    import std.format : format;
    import dextool.plugin.mutate.backend.report.html.nodes;
    import dextool.plugin.mutate.backend.report.utility;

    auto statsh = defaultHtml(format("Mutation Testing Report %(%s %) %s",
            humanReadableKinds, Clock.currTime));
    statsh.preambleBody.n("style".Tag)
        .put(`.stat_tbl {border-collapse:collapse; border-spacing: 0;border-style: solid;border-width:1px;}`)
        .put(`.stat_tbl td{border-style: none;}`);

    auto mut_stat = reportStatistics(db, kinds);
    linesAsTable(statsh.body_, mut_stat.toString).putAttr("class", "stat_tbl");
    auto dead_tcstat = reportDeadTestCases(db);
    linesAsTable(statsh.body_, dead_tcstat.toString).putAttr("class", "stat_tbl");
    auto tc_overlap = reportTestCaseFullOverlap(db, kinds);
    linesAsTable(statsh.body_, tc_overlap.toString).putAttr("class", "stat_tbl");

    return statsh;
}
