/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_test_case_similarity;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    tmplDefaultTable, tmplDefaultMatrixTable;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

auto makeTestCaseSimilarityAnalyse(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, js_similarity));

    doc.title(format("Test Case Similarity Analyse %(%s %) %s",
            humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");
    doc.mainBody.addChild("p", "This is the similarity between test cases.");
    {
        auto p = doc.mainBody.addChild("p");
        p.addChild("b", "Note");
        p.appendText(": The analysis is based on the mutants that the test cases kill; thus, it is dependent on the mutation operators that are used when generating the report.");
    }

    toHtml(db, reportTestCaseSimilarityAnalyse(db, kinds, 5), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(ref Database db, TestCaseSimilarityAnalyse result, Element root) {
    import std.algorithm : sort, map;
    import std.array : array;
    import std.conv : to;
    import std.path : buildPath;
    import cachetools : CacheLRU;
    import dextool.cachetools;
    import dextool.plugin.mutate.backend.database : spinSqlQuery, MutationId;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
    import dextool.type : Path;

    auto link_cache = new CacheLRU!(MutationId, string);
    link_cache.ttl = 30; // magic number
    Path getPath(MutationId id) {
        return dextool.cachetools.cacheToolsRequire(link_cache, id, {
            auto path = spinSqlQuery!(() => db.getPath(id)).get;
            return format!"%s#%s"(buildPath(htmlFileDir, pathToHtmlLink(path)), id);
        }()).Path;
    }

    //const distances = result.distances.length;
    const test_cases = result.similarities.byKey.array.sort!((a, b) => a < b).array;

    //auto mat = tmplDefaultMatrixTable(root, test_cases.map!(a => a.name.idup).array);

    root.addChild("p", "The intersection column is the mutants that are killed by both the test case in the heading and in the column Test Case.")
        .appendText(
                " The difference column are the mutants that are only killed by the test case in the heading.");
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
    foreach (const tc; test_cases) {
        // Containers allows for hiding a table by clicking the corresponding header.
        // Defaults to hiding tables.
        auto comp_container = root.addChild("div").addClass("comp_container");
        auto heading = comp_container.addChild("h2").addClass("tbl_header");
        heading.addChild("i").addClass("right");
        heading.appendText(" ");
        heading.appendText(tc.name);
        auto tbl_container = comp_container.addChild("div").addClass("tbl_container");
        tbl_container.setAttribute("style", "display: none;");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Test Case", "Similarity", "Difference", "Intersection"
                ]);
        foreach (const d; result.similarities[tc]) {
            auto r = tbl.appendRow();
            r.addChild("td", d.testCase.name);
            r.addChild("td", format("%#.3s", d.similarity));
            auto difference = r.addChild("td");
            foreach (const mut; d.difference) {
                auto link = difference.addChild("a", mut.to!string);
                link.href = getPath(mut);
                difference.appendText(" ");
            }
            auto similarity = r.addChild("td");
            foreach (const mut; d.intersection) {
                auto link = similarity.addChild("a", mut.to!string);
                link.href = getPath(mut);
                similarity.appendText(" ");
            }
        }
    }
}
