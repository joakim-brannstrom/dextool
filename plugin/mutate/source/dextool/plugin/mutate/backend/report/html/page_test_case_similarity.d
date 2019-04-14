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

import arsd.dom : Document, Element, require, Table;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.html.constants;
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
    doc.title(format("Test Case Similarity Analyse %(%s %) %s",
            humanReadableKinds, Clock.currTime));
    doc.mainBody.addChild("p", "This is the similarity between test cases.")
        .appendText(" The closer to 1.0 the more similare the test cases are in what they verify.");
    {
        auto p = doc.mainBody.addChild("p");
        p.addChild("b", "Note");
        p.appendText(": The analyse is based on the mutants that the test cases kill thus it is dependent on the mutation operators that are used when generating the report.");
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
    import dextool.plugin.mutate.backend.database : spinSqlQuery, MutationId;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
    import dextool.type : Path;

    auto link_cache = new CacheLRU!(MutationId, string);
    link_cache.ttl = 30; // magic number
    Path getPath(MutationId id) {
        typeof(return) rval;
        auto q = link_cache.get(id);
        if (q.isNull) {
            auto path = spinSqlQuery!(() => db.getPath(id));
            rval = format!"%s#%s"(buildPath(htmlFileDir, pathToHtmlLink(path)), id);
            link_cache.put(id, rval);
        } else {
            rval = q.get;
        }
        return rval;
    }

    //const distances = result.distances.length;
    const test_cases = result.similarities.byKey.array.sort!((a, b) => a < b).array;

    //auto mat = tmplDefaultMatrixTable(root, test_cases.map!(a => a.name.idup).array);

    root.addChild("p", "The intersection column is the mutants that are killed by both the test case in the heading and in the column Test Case.")
        .appendText(
                " The difference column are the mutants that are only killed by the test case in the heading.");

    foreach (const tc; test_cases) {
        root.addChild("h2", tc.name);
        auto tbl = tmplDefaultTable(root, [
                "Test Case", "Similarity", "Intersection", "Difference"
                ]);
        foreach (const d; result.similarities[tc]) {
            auto r = tbl.appendRow();
            r.addChild("td", d.testCase.name);
            r.addChild("td", d.value.to!string);
            auto similarity = r.addChild("td");
            foreach (const mut; d.intersection) {
                auto link = similarity.addChild("a", mut.to!string);
                link.href = getPath(mut);
                similarity.appendText(" ");
            }
            auto difference = r.addChild("td");
            foreach (const mut; d.difference) {
                auto link = difference.addChild("a", mut.to!string);
                link.href = getPath(mut);
                difference.appendText(" ");
            }
        }
    }
}