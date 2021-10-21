/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_worklist;

import logger = std.experimental.logger;
import std.array : empty;
import std.conv : to;
import std.datetime : Clock;
import std.exception : collectException;
import std.format : format;
import std.traits : EnumMembers;
import std.typecons : tuple;

import arsd.dom : Document, Element, Table, RawSource;
import miniorm : spinSql;
import my.path : AbsolutePath, Path;
import my.optional;

import dextool.cachetools;
import dextool.plugin.mutate.backend.database : Database, MutantInfo2;
import dextool.plugin.mutate.backend.report.html.constants : HtmlStyle = Html;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    dashboardCss, tmplSortableTable;
import dextool.plugin.mutate.backend.report.html.utility : pathToHtmlLink, toShortDate;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.type : Mutation;

@safe:

void makeWorklistPage(ref Database db, Element root, const AbsolutePath mutantPageFname) @trusted {
    root.addChild("a", "Worklist").href = mutantPageFname.baseName;
    makePage(db, mutantPageFname);
}

private:

void makePage(ref Database db, const AbsolutePath pageFname) @system {
    import std.algorithm : map, filter;
    import std.path : buildPath;
    import dextool.plugin.mutate.backend.database : IterateMutantRow2, MutationId;

    auto doc = tmplBasicPage.dashboardCss;
    scope (success)
        () {
        import std.stdio : File;

        auto fout = File(pageFname, "w");
        fout.write(doc.toPrettyString);
    }();

    doc.title(format("Worklist %s", Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");

    {
        auto data = dashboard();
        auto style = doc.root.childElements("head")[0].addChild("style");
        style.addChild(new RawSource(doc, data.bootstrapCss.get));
        style.addChild(new RawSource(doc, data.dashboardCss.get));
        style.addChild(new RawSource(doc, tmplDefaultCss));

        auto script = doc.root.childElements("head")[0].addChild("script");
        script.addChild(new RawSource(doc, jsIndex));
    }

    auto root = doc.mainBody;
    root.addChild("p", "Priority: in what order the mutants are tested, highest priority first.");
    root.addChild("p", "Tested: date when the mutant was last tested/executed.");

    auto tbl = tmplSortableTable(root, ["Link", "Priority", "Tested", "Status"]);

    static string toLinkPath(Path path, MutationId id) {
        return format!"%s#%s"(buildPath(HtmlStyle.fileDir, pathToHtmlLink(path)), id);
    }

    foreach (data; spinSql!(() => db.worklistApi.getWorklist).map!(
            a => spinSql!(() => tuple(a.prio, db.mutantApi.getMutantInfo(a.id))))
            .filter!(a => a[1].hasValue)
            .map!(a => tuple(a[0], a[1].orElse(MutantInfo2.init)))) {
        auto mut = data[1];
        auto r = tbl.appendRow;

        r.addChild("td").addChild("a", format("%s:%s", mut.file,
                mut.sloc.line)).href = toLinkPath(mut.file, mut.id);
        r.addChild("td", data[0].get.to!string);
        r.addChild("td", mut.status == Mutation.Status.unknown ? "" : mut.updated.toShortDate);
        r.addChild("td", mut.status.to!string);
    }
}
