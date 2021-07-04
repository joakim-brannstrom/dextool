/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_mutant;

import logger = std.experimental.logger;
import std.array : empty;
import std.conv : to;
import std.datetime : Clock;
import std.format : format;
import std.traits : EnumMembers;

import arsd.dom : Document, Element, require, Table, RawSource, Link;
import my.path : AbsolutePath, Path;

import dextool.cachetools;
import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : reportSelectedAliveMutants;
import dextool.plugin.mutate.backend.report.html.constants : HtmlStyle = Html, DashboardCss;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    tmplDefaultTable, dashboardCss, tmplDefaultMatrixTable, tmplSortableTable;
import dextool.plugin.mutate.backend.report.html.utility : pathToHtmlLink, toShortDate;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

@safe:

void makeMutantPage(ref Database db, ref const ConfigReport conf,
        const(Mutation.Kind)[] kinds, const AbsolutePath mutantPageFname, string tag, Element root) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Mutants");

    root.addChild("a", "All mutants").href = mutantPageFname.baseName;

    makeAllMutantsPage(db, kinds, mutantPageFname);
    makeHighInterestMutants(db, kinds, conf.highInterestMutantsNr, root);
}

private:

immutable string[Mutation.Status] statusDescription;
immutable string[Mutation.Status] statusColor;

shared static this() @trusted {
    statusDescription = cast(immutable)[
        Mutation.Status.unknown
        : "Mutants that haven't been tested yet.",
        Mutation.Status.alive: "No test case failed when the mutant is tested.",
        Mutation.Status.killed: "At least one test case fail when the mutant is tested.",
        Mutation.Status.killedByCompiler
        : "The compiler found and killed the mutant.",
        Mutation.Status.timeout
        : "The test suite never terminate, infinite loop, when the mutant is tested.",
        Mutation.Status.noCoverage: "The mutant is never executed by the test suite.",
        Mutation.Status.equivalent
        : "No change in the test case binaries happens when the mutant is injected and compiled.",
        Mutation.Status.skipped
        : "The mutant is skipped because another mutant that covers it survived (is alive)."
    ];

    statusColor = cast(immutable)[
        //Mutation.Status.unknown:,
        // light red
        Mutation.Status.alive: "background-color: #ff9980",
        // light green
        Mutation.Status.killed: "background-color: #b3ff99",
        Mutation.Status.killedByCompiler: "background-color: #b3ff99",
        Mutation.Status.timeout: "background-color: #b3ff99",
        Mutation.Status.noCoverage: "background-color: #ff9980",
        //Mutation.Status.equivalent:,
        //Mutation.Status.skipped:,
    ];
}

void makeAllMutantsPage(ref Database db, const(Mutation.Kind)[] kinds, const AbsolutePath pageFname) @system {
    auto doc = tmplBasicPage.dashboardCss;
    scope (success)
        () {
        import std.stdio : File;

        auto fout = File(pageFname, "w");
        fout.write(doc.toPrettyString);
    }();

    doc.title(format("Mutants %s", Clock.currTime));
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

    const tabGroupName = "mutant_status";
    Element[Mutation.Status] tabLink;

    { // tab links
        auto tab = root.addChild("div").addClass("tab");
        foreach (const status; [EnumMembers!(Mutation.Status)]) {
            auto b = tab.addChild("button").addClass("tablinks")
                .addClass("tablinks_" ~ tabGroupName);
            b.setAttribute("onclick", format!`openTab(event, '%s', '%s')`(status, tabGroupName));
            b.appendText(status.to!string);
            tabLink[status] = b;
        }
    }

    Table[Mutation.Status] tabContent;
    foreach (const status; [EnumMembers!(Mutation.Status)]) {
        auto div = root.addChild("div").addClass("tabcontent")
            .addClass("tabcontent_" ~ tabGroupName).setAttribute("id", status.to!string);
        div.addChild("p", statusDescription[status]);
        tabContent[status] = tmplSortableTable(div, [
                "Link", "Priority", "ExitCode", "Tested"
                ]);
    }

    long[Mutation.Status] statusCnt;
    addMutants(db, kinds, tabContent, statusCnt);

    foreach (a; statusCnt.byKeyValue) {
        tabLink[a.key].appendText(format!" %s"(a.value));
        if (auto c = a.key in statusColor)
            tabLink[a.key].style = *c;
    }
}

void addMutants(ref Database db, const(Mutation.Kind)[] kinds,
        ref Table[Mutation.Status] content, ref long[Mutation.Status] statusCnt) @system {
    import std.path : buildPath;
    import dextool.plugin.mutate.backend.database : IterateMutantRow2, MutationId;

    static string toLinkPath(Path path, MutationId id) {
        return format!"%s#%s"(buildPath(HtmlStyle.fileDir, pathToHtmlLink(path)), id);
    }

    void mutant(ref const IterateMutantRow2 mut) {
        statusCnt[mut.mutant.status] += 1;

        auto r = content[mut.mutant.status].appendRow;

        r.addChild("td").addChild("a", format("%s:%s", mut.file,
                mut.sloc.line)).href = toLinkPath(mut.file, mut.id);
        r.addChild("td", mut.prio.get.to!string);
        r.addChild("td", mut.exitStatus.get.to!string);
        r.addChild("td", mut.tested.toShortDate);
    }

    db.iterateMutants(kinds, &mutant);
}

void makeHighInterestMutants(ref Database db, const(Mutation.Kind)[] kinds,
        typeof(ConfigReport.highInterestMutantsNr) showInterestingMutants, Element root) @trusted {
    import std.path : buildPath;
    import dextool.plugin.mutate.backend.report.html.utility : pathToHtmlLink;

    const sample = reportSelectedAliveMutants(db, kinds, showInterestingMutants.get);
    if (sample.highestPrio.empty)
        return;

    DashboardCss.h3(root, "High Interest Mutants");

    if (sample.highestPrio.length != 0) {
        root.addChild("p", format("This list the %s mutants that affect the most source code and has survived.",
                sample.highestPrio.length));
        auto tbl_container = root.addChild("div").addClass("tbl_container");
        auto tbl = tmplDefaultTable(tbl_container, [
                "Link", "Tested", "Priority"
                ]);

        foreach (const mutst; sample.highestPrio) {
            const mut = sample.mutants[mutst.statusId];
            auto r = tbl.appendRow();
            r.addChild("td").addChild("a", format("%s:%s", mut.file,
                    mut.sloc.line)).href = format("%s#%s", buildPath(HtmlStyle.fileDir,
                    pathToHtmlLink(mut.file)), mut.id.get);
            r.addChild("td", mutst.updated.toString);
            r.addChild("td", mutst.prio.get.to!string);
        }
    }
}
