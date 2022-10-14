/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_test_group_similarity;

import logger = std.experimental.logger;
import std.format : format;
import std.datetime : Clock, dur;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : TestGroupSimilarity,
    reportTestGroupsSimilarity;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.resource : jsTableOnClick;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    tmplDefaultTable, tmplDefaultMatrixTable, dashboardCss;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;

auto makeTestGroupSimilarityAnalyse(ref Database db, ref const ConfigReport conf) @trusted {
    auto doc = tmplBasicPage.dashboardCss;
    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, jsTableOnClick));
    doc.title("Test Group Similarity Analyse");
    doc.mainBody.addChild("p",
            "This is the similarity between test groups as specified in the dextool mutate configuration file.")
        .appendText(" The closer to 1.0 the more similare the test groups are in what they verify.");
    {
        auto p = doc.mainBody.addChild("p");
        p.addChild("b", "Note");
        p.appendText(": The analyse is based on the mutants that the test cases kill thus it is dependent on the mutation operators that are used when generating the report.");
    }

    toHtml(db, reportTestGroupsSimilarity(db, conf.testGroups), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(ref Database db, TestGroupSimilarity result, Element root) {
    import std.algorithm : sort, map;
    import std.array : array;
    import std.conv : to;
    import std.path : buildPath;
    import dextool.cachetools;
    import dextool.plugin.mutate.backend.database : spinSql, MutationStatusId;
    import dextool.plugin.mutate.backend.report.html.utility : pathToHtmlLink;
    import dextool.type : Path;

    auto getPath = nullableCache!(MutationStatusId, string, (MutationStatusId id) {
        auto path = spinSql!(() => db.mutantApi.getPath(id)).get;
        return format!"%s#%s"(buildPath("..", Html.fileDir, pathToHtmlLink(path)), id.get);
    })(0, 30.dur!"seconds");

    const test_groups = result.similarities.byKey.array.sort!((a, b) => a < b).array;

    root.addChild("p", "The intersection column are the mutants that are killed by both the test group in the heading and in the column Test Group.")
        .appendText(
                " The difference column are the mutants that are only killed by the test group in the heading.");
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
    foreach (const tg; test_groups) {
        auto comp_container = root.addChild("div").addClass("comp_container");
        auto heading = comp_container.addChild("h2").addClass("tbl_header");
        heading.addChild("i").addClass("right");
        heading.appendText(format(" %s (%s)", tg.description, tg.name));
        comp_container.addChild("p", tg.userInput);
        auto tbl_container = comp_container.addChild("div").addClass("tbl_container");
        tbl_container.setAttribute("style", "display: none;");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Test Group", "Similarity", "Difference", "Intersection"
                ]);
        foreach (const d; result.similarities[tg]) {
            auto r = tbl.appendRow();
            r.addChild("td", d.comparedTo.name);
            r.addChild("td", format("%#.3s", d.similarity));
            auto difference = r.addChild("td");
            foreach (const mut; d.difference) {
                auto link = difference.addChild("a", mut.to!string);
                link.href = getPath(mut).get;
                difference.appendText(" ");
            }
            auto similarity = r.addChild("td");
            foreach (const mut; d.intersection) {
                auto link = similarity.addChild("a", mut.to!string);
                link.href = getPath(mut).get;
                similarity.appendText(" ");
            }
        }
    }
}
