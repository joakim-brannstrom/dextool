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
import std.conv : to;
import std.format : format;

import arsd.dom : Document, Element, require, Table, RawSource, Link;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : reportSelectedAliveMutants;
import dextool.plugin.mutate.backend.report.html.constants : HtmlStyle = Html, DashboardCss;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplDefaultTable;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.type : Mutation;

void makeHighInterestMutants(ref Database db, const(Mutation.Kind)[] kinds, string tag, Element root) @trusted {
    import std.path : buildPath;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;

    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id",
            tag[1 .. $]), "High Interest Mutants");
    const sample = reportSelectedAliveMutants(db, kinds, 5);

    if (sample.highestPrio.length != 0) {
        root.addChild("p", format("This list the %s mutants that affect the most source code and has survived.",
                sample.highestPrio.length));
        auto tbl_container = root.addChild("div").addClass("tbl_container");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Link", "Discovered", "Last Updated", "Priority"
                ]);

        foreach (const mutst; sample.highestPrio) {
            const mut = sample.mutants[mutst.statusId];
            auto r = tbl.appendRow();
            r.addChild("td").addChild("a", format("%s:%s", mut.file,
                    mut.sloc.line)).href = format("%s#%s", buildPath(HtmlStyle.fileDir,
                    pathToHtmlLink(mut.file)), mut.id.get);
            r.addChild("td", mutst.added.isNull ? "unknown" : mutst.added.get.toString);
            r.addChild("td", mutst.updated.toString);
            r.addChild("td", mutst.prio.get.to!string);
        }
    }
}
