/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_long_term_view;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

auto makeLongTermView(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;
    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, js_index));
    doc.mainBody.setAttribute("onload", "init()");
    doc.title(format("Long Term View %(%s %) %s", humanReadableKinds, Clock.currTime));

    toHtml(reportSelectedAliveMutants(db, kinds, 10), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(const MutantSample mut_sample, Element root) {
    import std.path : buildPath;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;

    root.addChild("h2", "High Interest Mutants");

    if (mut_sample.hardestToKill.length != 0) {
        root.addChild("h3", "Longest surviving Mutants");
        root.addChild("p",
                "These mutants survived countless test runs.");
        auto tbl_container = root.addChild("div").addClass("tbl_container");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Link", "Discovered", "Last Updated", "Survived"
                ]);

        foreach (const mutst; mut_sample.hardestToKill) {
            const mut = mut_sample.mutants[mutst.statusId];
            auto r = tbl.appendRow();
            r.addChild("td").addChild("a", format("%s:%s", mut.file,
                    mut.sloc.line)).href = format("%s#%s", buildPath(htmlFileDir,
                    pathToHtmlLink(mut.file)), mut.id);
            r.addChild("td", mutst.added.isNull ? "unknown" : mutst.added.get.toString);
            r.addChild("td", mutst.updated.toString);
            r.addChild("td", format("%s times", mutst.testCnt));
        }
    }

    if (mut_sample.oldest.length != 0) {
        root.addChild("p", format("This is a list of the %s oldest mutants. This list contains information when they where last tested and had their status updated.",
                mut_sample.oldest.length));

        auto tbl_container = root.addChild("div").addClass("tbl_container");
        auto tbl = tmplDefaultTable(tbl_container, ["Link", "Updated"]);

        foreach (const mutst; mut_sample.oldest) {
            auto mut = mut_sample.mutants[mutst.id];
            auto r = tbl.appendRow();
            r.addChild("td").addChild("a", format("%s:%s", mut.file,
                    mut.sloc.line)).href = format("%s#%s", buildPath(htmlFileDir,
                    pathToHtmlLink(mut.file)), mut.id);
            r.addChild("td", mutst.updated.toString);
        }
    }
}
