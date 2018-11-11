/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_stats;

import logger = std.experimental.logger;
import std.algorithm : sort, map, filter, count;
import std.conv : to;
import std.datetime : Clock, dur;
import std.format : format;
import std.typecons : tuple;
import std.xml : encode;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.nodes;
import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

@safe:

auto makeStats(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) {
    import dextool.plugin.mutate.type : ReportSection;
    import dextool.set;

    auto sections = setFromList(conf.reportSection);

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
    selectedMutants(reportSelectedAliveMutants(db, kinds, 1), statsh.body_);
    if (ReportSection.tc_killed_no_mutants in sections)
        deadTestCase(reportDeadTestCases(db), statsh.body_);
    if (ReportSection.tc_full_overlap in sections
            || ReportSection.tc_full_overlap_with_mutation_id in sections)
        overlapTestCase(reportTestCaseFullOverlap(db, kinds), statsh.body_);

    if (conf.testGroups.length != 0)
        statsh.body_.n("h2".Tag).put("Test Groups");
    foreach (tg; conf.testGroups)
        testGroups(reportTestGroups(db, kinds, tg), statsh.body_);

    return statsh;
}

private:

immutable tableStyle = "overlap_tbl";
immutable tableColumnHdrStyle = "tg-g59y";
immutable tableRowStyle = "tg-0lax";
immutable tableRowDarkStyle = "tg-0lax_dark";

void overallStat(const MutationStat s, HtmlNode n) {
    n.n("h2".Tag).put("Summary");

    n.n("p".Tag).put(format("Mutation Score %s", s.score));

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

void selectedMutants(const MutantSample mut_sample, HtmlNode n) {
    import std.path : buildPath;

    n.n("h2".Tag).put("High Interest Mutants");

    if (mut_sample.oldest.length != 0) {
        with (n.n("p".Tag)) {
            put("The mutant with the oldest status where last updated ");
            put(mut_sample.oldest[0].updated.toString);
        }

        const mut = mut_sample.mutants[mut_sample.oldest[0].id];
        n.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(mut.file)),
                format("%s:%s", mut.file, mut.sloc.line), mut.id.to!string));
    }

    if (!mut_sample.hardestToKillStatus.isNull && !mut_sample.hardestToKillMutant.isNull) {
        auto mut_st = mut_sample.hardestToKillStatus.get;
        auto mut = mut_sample.hardestToKillMutant.get;

        n.n("h3".Tag).put("Longest Surviving Mutant");
        n.n("p".Tag)
            .put(
                    "This mutant has survived countless test runs. Slay it and be the hero of the team.");
        n.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(mut.file)),
                format("%s:%s", mut.file, mut.sloc.line), mut.id.to!string));

        auto tbl = HtmlTable.make;
        n.put(tbl.root);
        tbl.root.putAttr("class", "overlap_tbl");
        tbl.root.putAttr("class", "stat_tbl");
        foreach (c; ["Information", ""])
            tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);
        foreach (const d; [tuple("Last Updated", mut_st.updated.toString),
                tuple("Discovered", mut_st.added.isNull ? "unknown" : mut_st.added.get.toString),
                tuple("Survived", format("%s times", mut_st.testCnt))]) {
            auto r = tbl.newRow;
            r.td.put(d[0]);
            r.td.put(d[1].to!string);
        }
    }

    if (mut_sample.latest.length != 0) {
        n.n("h3".Tag).put("Latest Surviving Mutants");
        n.n("p".Tag)
            .put(
                    "This mutants where newly tested and survived. It is a high probability that they are relevant to you.");

        auto tbl = HtmlTable.make;
        n.put(tbl.root);
        tbl.root.putAttr("class", "overlap_tbl");
        foreach (c; ["Link", "Date"])
            tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);
        foreach (const mutst; mut_sample.latest) {
            const mut = mut_sample.mutants[mutst.id];
            auto r = tbl.newRow;
            r.td.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(mut.file)),
                    format("%s:%s", mut.file, mut.sloc.line), mut.id.to!string));
            r.td.put(mutst.updated.toString);
        }
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
        tbl.newRow.td.put(tc.name.encode);
    }
}

void overlapTestCase(const TestCaseOverlapStat s, HtmlNode n) {
    import std.array : array;
    import std.range : enumerate;

    if (s.total == 0)
        return;

    n.n("h2".Tag).put("Overlapping Test Cases");
    n.n("p".Tag).put("These test has killed exactly the same mutants. This is an indication that they verify the same aspects. This can mean that some of them may be redundant.");

    n.n("p".Tag).put(s.sumToString);

    auto tbl = HtmlTable.make;
    n.put(tbl.root);
    tbl.root.putAttr("class", tableStyle);
    tbl.putColumn("Test Case").putAttr("class", tableColumnHdrStyle);
    tbl.putColumn("Count").putAttr("class", tableColumnHdrStyle);
    tbl.putColumn("Mutation IDs").putAttr("class", tableColumnHdrStyle);

    foreach (tcs; s.tc_mut.byKeyValue.filter!(a => a.value.length > 1).enumerate) {
        bool first = true;
        string cls = () {
            if (tcs.index % 2 == 0)
                return tableRowStyle;
            return tableRowDarkStyle;
        }();

        // TODO this is a bit slow. use a DB row iterator instead.
        foreach (name; tcs.value.value.map!(id => s.name_tc[id].idup).array.sort) {
            auto r = tbl.newRow;
            if (first) {
                r.td.put(name.encode).putAttr("class", cls);
                r.td.put(s.mutid_mut[tcs.value.key].length.to!string).putAttr("class", cls);
                r.td.put(format("%(%s %)", s.mutid_mut[tcs.value.key])).putAttr("class", cls);
            } else {
                r.td.put(name).putAttr("class", cls);
            }
            first = false;
        }
    }
}

void testGroups(const TestGroupStat test_g, HtmlNode n) {
    import std.array : array;
    import std.path : buildPath;
    import std.range : enumerate;
    import dextool.plugin.mutate.backend.mutation_type : toUser;

    n.n("h3".Tag).put(test_g.description);

    auto stat_tbl = HtmlTable.make;
    n.put(stat_tbl.root);
    stat_tbl.root.putAttr("class", "overlap_tbl");
    foreach (const d; [tuple("Mutation Score", test_g.stats.score.to!string),
            tuple("Alive", test_g.stats.alive.to!string), tuple("Total",
                test_g.stats.total.to!string)]) {
        auto r = stat_tbl.newRow;
        r.td.put(d[0]);
        r.td.put(d[1]);
    }

    with (n.n("p".Tag)) {
        put("Mutation data per file.");
        put("The killed mutants are those that where killed by this test group.");
        put("Therefor the total here is less than the reported total.");
    }
    auto file_tbl = HtmlTable.make;
    n.put(file_tbl.root);
    file_tbl.root.putAttr("class", "overlap_tbl");
    foreach (c; ["File", "Alive", "Killed"])
        file_tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);

    foreach (const pkv; test_g.files
            .byKeyValue
            .map!(a => tuple(a.key, a.value.dup))
            .array
            .sort!((a, b) => a[1] < b[1])) {
        auto r = file_tbl.newRow;
        const path = test_g.files[pkv[0]];
        r.td.put(path);

        auto alive_ids = r.td;
        if (auto alive = pkv[0] in test_g.alive) {
            foreach (a; (*alive).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                alive_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                        format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                alive_ids.put(" ");
            }
        }

        auto killed_ids = r.td;
        if (auto killed = pkv[0] in test_g.killed) {
            foreach (a; (*killed).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                killed_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                        format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                killed_ids.put(" ");
            }
        }
    }

    auto tc_tbl = HtmlTable.make;
    n.put(tc_tbl.root);
    tc_tbl.root.putAttr("class", "overlap_tbl");
    tc_tbl.putColumn("Test Cases").putAttr("class", tableColumnHdrStyle);
    foreach (tc; test_g.testCases) {
        auto r = tc_tbl.newRow;
        r.td.put(tc.name);
    }
}
