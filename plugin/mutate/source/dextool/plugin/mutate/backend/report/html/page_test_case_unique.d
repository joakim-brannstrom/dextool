/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_test_case_unique;

import logger = std.experimental.logger;
import std.format : format;
import std.datetime : Clock, dur;

import arsd.dom : Element, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : TestCaseUniqueness,
    reportTestCaseUniqueness;
import dextool.plugin.mutate.backend.report.html.constants : htmlFileDir;
import dextool.plugin.mutate.backend.resource : jsTableOnClick;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

auto makeTestCaseUnique(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    auto doc = tmplBasicPage;

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, jsTableOnClick));

    doc.title(format("Test Case Uniqueness %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");
    doc.mainBody.addChild("p", "This report contains the test cases that uniquely kill mutants, which those mutants are and test cases that aren't unique.");

    toHtml(db, reportTestCaseUniqueness(db, kinds), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(ref Database db, TestCaseUniqueness result, Element root) {
    import std.algorithm : sort, map;
    import std.array : array;
    import std.conv : to;
    import std.path : buildPath;
    import dextool.cachetools;
    import dextool.plugin.mutate.backend.database : spinSql, MutationId;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
    import dextool.type : Path;

    auto getPath = nullableCache!(MutationId, string, (MutationId id) {
        auto path = spinSql!(() => db.getPath(id)).get;
        return format!"%s#%s"(buildPath(htmlFileDir, pathToHtmlLink(path)), id);
    })(0, 30.dur!"seconds");

    with (root.addChild("button", "expand all")) {
        setAttribute("type", "button");
        setAttribute("id", "expand_all");
    }
    with (root.addChild("button", "collapse all")) {
        setAttribute("type", "button");
        setAttribute("id", "collapse_all");
    }

    foreach (const k; result.uniqueKills.byKey.array.sort) {
        // Containers allows for hiding a table by clicking the corresponding header.
        // Defaults to hiding tables.
        auto comp_container = root.addChild("div").addClass("comp_container");
        auto heading = comp_container.addChild("h2").addClass("tbl_header");
        heading.addChild("i").addClass("right");
        heading.appendText(" ");
        heading.appendText(k.name);
        auto tbl_container = comp_container.addChild("div").addClass("tbl_container");
        tbl_container.setAttribute("style", "display: none;");
        auto tbl = tmplDefaultTable(tbl_container, ["Mutation ID"]);

        auto r = tbl.appendRow();
        auto mut_ids = r.addChild("td");
        foreach (const m; result.uniqueKills[k].sort) {
            auto link = mut_ids.addChild("a", m.to!string);
            link.href = getPath(m).get;
            mut_ids.appendText(" ");
        }
    }

    {
        root.addChild("p", "These are test cases that have no unique kills");
        auto tbl = tmplDefaultTable(root, ["Test Case"]);
        foreach (const tc; result.noUniqueKills.sort) {
            auto r = tbl.appendRow;
            r.addChild("td", tc.name);
        }
    }
}
