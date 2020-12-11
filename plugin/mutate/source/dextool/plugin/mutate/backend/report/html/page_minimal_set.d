/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_minimal_set;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MinimalTestSet, reportMinimalSet;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    tmplDefaultTable, tmplDefaultMatrixTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

auto makeMinimalSetAnalyse(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, jsTableOnClick));

    doc.title(format("Minimal Set Analyse %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");
    doc.mainBody.addChild("p",
            "This are the minimal set of mutants that result in the mutation score.");

    auto p = doc.mainBody.addChild("p");

    toHtml(reportMinimalSet(db, kinds), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(MinimalTestSet min_set, Element root) {
    import core.time : Duration;
    import std.conv : to;

    {
        root.addChild("p",
                "The tables are hidden by default, click on the corresponding header to display a table.");
        with (root.addChild("button", "expand all")) {
            setAttribute("type", "button");
            setAttribute("id", "expand_all");
        }
        with (root.addChild("button", "collapse all")) {
            setAttribute("type", "button");
            setAttribute("id", "collapse_all");
        }
        auto comp_container = root.addChild("div").addClass("comp_container");
        auto heading = comp_container.addChild("h2").addClass("tbl_header");
        heading.addChild("i").addClass("right");
        heading.appendText(format!" Ineffective Test Cases (%s/%s %s)"(min_set.redundant.length,
                min_set.total, cast(double) min_set.redundant.length / cast(double) min_set.total));
        comp_container.addChild("p",
                "These test cases do not contribute towards the mutation score.");
        auto tbl_container = comp_container.addChild("div").addClass("tbl_container");
        tbl_container.setAttribute("style", "display: none;");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Test Case", "Killed", "Sum of test time"
                ]);

        Duration sum;
        foreach (const tc; min_set.redundant) {
            auto r = tbl.appendRow();
            r.addChild("td", tc.name);
            r.addChild("td", min_set.testCaseTime[tc.name].killedMutants.to!string);
            r.addChild("td", min_set.testCaseTime[tc.name].time.to!string);
            sum += min_set.testCaseTime[tc.name].time;
        }
        tbl_container.addChild("p", format("Total test time: %s", sum));
    }
    {
        auto comp_container = root.addChild("div").addClass("comp_container");
        auto heading = comp_container.addChild("h2").addClass("tbl_header");
        heading.addChild("i").addClass("right");
        heading.appendText(format!" Minimal Set (%s/%s %s)"(min_set.minimalSet.length,
                min_set.total, cast(double) min_set.minimalSet.length / cast(double) min_set.total));
        comp_container.addChild("p",
                "This is the minimum set of tests that achieve the mutation score.");

        auto tbl_container = comp_container.addChild("div").addClass("tbl_container");
        tbl_container.setAttribute("style", "display: none;");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Test Case", "Killed", "Sum of test time"
                ]);

        Duration sum;
        foreach (const tc; min_set.minimalSet) {
            auto r = tbl.appendRow();
            r.addChild("td", tc.name);
            r.addChild("td", min_set.testCaseTime[tc.name].killedMutants.to!string);
            r.addChild("td", min_set.testCaseTime[tc.name].time.to!string);
            sum += min_set.testCaseTime[tc.name].time;
        }
        tbl_container.addChild("p", format("Total test time: %s", sum));
    }
}
