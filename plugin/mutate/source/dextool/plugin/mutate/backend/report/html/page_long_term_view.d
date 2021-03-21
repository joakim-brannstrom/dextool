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

import arsd.dom : Document, Element, require, Table, RawSource, Link;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MutantSample, reportSelectedAliveMutants;
import dextool.plugin.mutate.backend.report.html.constants : HtmlStyle = Html, DashboardCss;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    tmplDefaultTable, dashboardCss;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

void makeLongTermView(ref Database db, const(Mutation.Kind)[] kinds, string tag, Element root) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id",
            tag[1 .. $]), "High Interest Mutants");
    toHtml(reportSelectedAliveMutants(db, kinds, 5), root);
}

private:

void toHtml(const MutantSample sample, Element root) {
    import std.path : buildPath;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;

    if (sample.hardestToKill.length != 0) {
        root.addChild("p", format("This list the %s mutants that have survived the most test runs.",
                sample.hardestToKill.length));
        auto tbl_container = root.addChild("div").addClass("tbl_container");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Link", "Discovered", "Last Updated", "Survived"
                ]);

        foreach (const mutst; sample.hardestToKill) {
            const mut = sample.mutants[mutst.statusId];
            auto r = tbl.appendRow();
            r.addChild("td").addChild("a", format("%s:%s", mut.file,
                    mut.sloc.line)).href = format("%s#%s", buildPath(HtmlStyle.fileDir,
                    pathToHtmlLink(mut.file)), mut.id.get);
            r.addChild("td", mutst.added.isNull ? "unknown" : mutst.added.get.toString);
            r.addChild("td", mutst.updated.toString);
            r.addChild("td", format("%s times", mutst.testCnt));
        }
    }

    if (sample.oldest.length != 0) {
        root.addChild("p", format("This list is the %s oldest mutants based on when they where last updated",
                sample.oldest.length));

        auto tbl_container = root.addChild("div").addClass("tbl_container");
        auto tbl = tmplDefaultTable(tbl_container, ["Link", "Updated"]);

        foreach (const mutst; sample.oldest) {
            auto mut = sample.mutants[mutst.id];
            auto r = tbl.appendRow();
            r.addChild("td").addChild("a", format("%s:%s", mut.file,
                    mut.sloc.line)).href = format("%s#%s", buildPath(HtmlStyle.fileDir,
                    pathToHtmlLink(mut.file)), mut.id.get);
            r.addChild("td", mutst.updated.toString);
        }
    }
}
