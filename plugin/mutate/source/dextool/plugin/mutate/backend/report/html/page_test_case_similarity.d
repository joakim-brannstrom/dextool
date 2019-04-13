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
    doc.mainBody.addChild("p", "This is the distance between test cases.").appendText(
            " The closer to 1.0 the more similare the test cases are in what they verify.").appendText(" The analyse is based on the mutants that the test cases kill thus it is dependent on the mutation operators that are used when generating the report.");

    toHtml(reportTestCaseSimilarityAnalyse(db, kinds, 5), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(TestCaseSimilarityAnalyse result, Element root) {
    import std.algorithm : sort, map;
    import std.array : array;
    import std.conv : to;
    import std.range : take;

    //const distances = result.distances.length;
    const test_cases = result.distances.byKey.array.sort!((a, b) => a < b).array;

    //auto mat = tmplDefaultMatrixTable(root, test_cases.map!(a => a.name.idup).array);

    foreach (const tc; test_cases) {
        root.addChild("h2", tc.name);
        auto tbl = tmplDefaultTable(root, ["Test Case", "Similarity"]);
        foreach (const d; result.distances[tc]) {
            auto r = tbl.appendRow();
            r.addChild("td", d.testCase.name);
            r.addChild("td", d.value.to!string);
        }
    }
}
