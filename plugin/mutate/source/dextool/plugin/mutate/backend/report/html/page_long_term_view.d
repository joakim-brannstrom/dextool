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
import std.algorithm : sort, map, filter, count;
import std.conv : to;
import std.datetime : Clock, dur;
import std.format : format;
import std.typecons : tuple;
import std.xml : encode;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.nodes;
import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

@safe:

auto makeLongTermView(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) {
    import dextool.plugin.mutate.backend.report.html.tmpl : addStateTableCss;

    auto root = defaultHtml(format("Long Term View %(%s %) %s", humanReadableKinds, Clock.currTime));
    auto s = root.preambleBody.n("style".Tag);
    addStateTableCss(s);

    toHtml(reportSelectedAliveMutants(db, kinds, 10), root.body_);

    return root;
}

private:

void toHtml(const MutantSample mut_sample, HtmlNode root) {
    import std.path : buildPath;

    root.n("h2".Tag).put("High Interest Mutants");

    if (mut_sample.hardestToKill.length != 0) {
        root.n("h3".Tag).put("Longest Surviving Mutant");
        root.n("p".Tag)
            .put(
                    "This mutants has survived countless test runs. Slay one or more of them to be the hero of the team.");

        auto tbl = HtmlTable.make;
        root.put(tbl.root);
        tbl.root.putAttr("class", "overlap_tbl");
        tbl.root.putAttr("class", "stat_tbl");
        foreach (c; ["Link", "Discovered", "Last Updated", "Survived"])
            tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);

        foreach (const mutst; mut_sample.hardestToKill) {
            const mut = mut_sample.mutants[mutst.statusId];
            auto r = tbl.newRow;

            r.td.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(mut.file)),
                    format("%s:%s", mut.file, mut.sloc.line), mut.id.to!string));
            r.td.put(mutst.added.isNull ? "unknown" : mutst.added.get.toString);
            r.td.put(mutst.updated.toString);
            r.td.put(format("%s times", mutst.testCnt));
        }
    }

    if (mut_sample.oldest.length != 0) {
        root.n("p".Tag).put(format("This is a list of the %s oldest mutants containing when they where last tested and thus had their status updated.",
                mut_sample.oldest.length));

        auto tbl = HtmlTable.make;
        root.put(tbl.root);
        tbl.root.putAttr("class", "overlap_tbl");
        foreach (c; ["Link", "Updated"])
            tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);

        foreach (const mutst; mut_sample.oldest) {
            auto mut = mut_sample.mutants[mutst.id];
            auto r = tbl.newRow;
            r.td.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(mut.file)),
                    format("%s:%s", mut.file, mut.sloc.line), mut.id.to!string));
            r.td.put(mutst.updated.toString);
        }
    }
}
