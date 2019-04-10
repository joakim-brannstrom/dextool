/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_redundant;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

auto makeRedundantAnalyse(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;
    doc.title(format("Redundant Analyse %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.addChild("p",
            "This are the minimal set of mutants that result in the mutation score.");

    toHtml(reportMinimalSet(db, kinds), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(MinimalTestSet min_set, Element root) {
    root.addChild("h2", format!"Ineffective Test Cases (%s/%s %s)"(min_set.redundant.length,
            min_set.total, cast(double) min_set.redundant.length / cast(double) min_set.total));
    root.addChild("p", "These test cases do not contribute towards the mutation score.");
    {
        auto tbl = tmplDefaultTable(root, ["Test Case"]);
        foreach (const tc; min_set.redundant) {
            auto r = tbl.appendRow();
            r.addChild("td", tc.name);
        }
    }

    root.addChild("h2", format!"Minimal Set (%s/%s %s)"(min_set.minimalSet.length,
            min_set.total, cast(double) min_set.minimalSet.length / cast(double) min_set.total));
    root.addChild("p", "This is the minimum set of tests that achieve the mutation score.");
    {
        auto tbl = tmplDefaultTable(root, ["Test Case"]);
        foreach (const tc; min_set.minimalSet) {
            auto r = tbl.appendRow();
            r.addChild("td", tc.name);
        }
    }
}
