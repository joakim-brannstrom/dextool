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
import dextool.plugin.mutate.backend.type : Mutation, toString;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.plugin.mutate.backend.report.html.utility : generatePopupHelp;
@safe:

void makeMutantPage(ref Database db, string tag, Element root, ref const ConfigReport conf,
        const(Mutation.Kind)[] kinds, const AbsolutePath mutantPageFname) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Mutants");
    root.addChild("a", "All mutants").href = mutantPageFname.baseName;
    makeAllMutantsPage(db, kinds, mutantPageFname);
    makeHighInterestMutants(db, kinds, conf.highInterestMutantsNr, root);
}

private:

string mixinMutantStatus() {
    string s;
    s ~= "enum MutantStatus {";
    foreach (a; [EnumMembers!(Mutation.Status)])
        s ~= a.to!string ~ ",";
    s ~= "nomut";
    s ~= "}";
    return s;
}

mixin(mixinMutantStatus);

MutantStatus toStatus(Mutation.Status s) {
    return cast(MutantStatus) s;
}

immutable string[MutantStatus] statusDescription;
immutable string[MutantStatus] statusColor;

shared static this() @trusted {
    statusDescription = cast(immutable)[
        MutantStatus.unknown: "Mutants that haven't been tested yet.",
        MutantStatus.alive: "No test case failed when the mutant is tested.",
        MutantStatus.killed: "At least one test case fail when the mutant is tested.",
        MutantStatus.killedByCompiler: "The compiler found and killed the mutant.",
        MutantStatus.timeout: "The test suite never terminate, infinite loop, when the mutant is tested.",
        MutantStatus.memOverload: "The test suite where terminated because the system memory limit triggered.",
        MutantStatus.noCoverage: "The mutant is never executed by the test suite.",
        MutantStatus.equivalent: "No change in the test case binaries happens when the mutant is injected and compiled.",
        MutantStatus.skipped: "The mutant is skipped because another mutant that covers it survived (is alive).",
        MutantStatus.nomut: "The mutant is manually marked as not interesting. There is no intention of writing a test to kill it."
    ];

    statusColor = cast(immutable)[
        //Mutation.Status.unknown:,
        // light red
        MutantStatus.alive: "background-color: #ff9980",
        // light green
        MutantStatus.killed: "background-color: #b3ff99",
        MutantStatus.killedByCompiler: "background-color: #b3ff99",
        MutantStatus.timeout: "background-color: #b3ff99",
        MutantStatus.memOverload: "background-color: #b3ff99",
        MutantStatus.noCoverage: "background-color: #ff9980",
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
    doc.mainBody.addChild("h1", "All mutants");
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
    Element[MutantStatus] tabLink;

    { // tab links
        auto tab = root.addChild("div").addClass("tab");
        foreach (const status; [EnumMembers!MutantStatus]) {
            auto b = tab.addChild("button").addClass("tablinks")
                .addClass("tablinks_" ~ tabGroupName);
            b.setAttribute("onclick", format!`openTab(event, '%s', '%s')`(status, tabGroupName));
            b.appendText(status.to!string);
            tabLink[status] = b;
        }
    }

    void addPopupHelp(Element e, string header) {
        switch(header) {
            case "Priority": 
                generatePopupHelp(e, "How important it is to kill the mutant. It is based on modified source code size.");
                break;
            case "ExitCode": 
                generatePopupHelp(e, "The exit code of the test suite when the mutant where killed. 1: normal");
                break;
            case "Tests": 
                generatePopupHelp(e, "Number of tests that killed the mutant (failed when it was executed).");
                break;
            case "Tested":
                generatePopupHelp(e, "Date when the mutant was last tested/executed.");
                break;
            default:
                break;
        }
    }

    Table[MutantStatus] tabContent;
    foreach (const status; [EnumMembers!MutantStatus]) {
        auto div = root.addChild("div").addClass("tabcontent")
            .addClass("tabcontent_" ~ tabGroupName).setAttribute("id", status.to!string);
        div.addChild("p", statusDescription[status]);
        tabContent[status] = tmplSortableTable(div, [
                "Link", "Priority", "ExitCode", "Tests", "Tested"
                ], &addPopupHelp);
    }

    long[MutantStatus] statusCnt;
    addMutants(db, kinds, tabContent, statusCnt);

    foreach (a; statusCnt.byKeyValue) {
        tabLink[a.key].appendText(format!" %s"(a.value));
        if (auto c = a.key in statusColor)
            tabLink[a.key].style = *c;
    }
}

void addMutants(ref Database db, const(Mutation.Kind)[] kinds,
        ref Table[MutantStatus] content, ref long[MutantStatus] statusCnt) @system {
    import std.path : buildPath;
    import dextool.plugin.mutate.backend.database : IterateMutantRow2, MutationId, MutationStatusId;

    static string toLinkPath(Path path, MutationStatusId id) {
        return format!"%s#%s"(buildPath(HtmlStyle.fileDir, pathToHtmlLink(path)), id);
    }

    void mutant(ref const IterateMutantRow2 mut) {
        const status = () {
            if (mut.attrs.isNoMut)
                return MutantStatus.nomut;
            return toStatus(mut.mutant.status);
        }();

        statusCnt[status] += 1;
        auto r = content[status].appendRow;

        r.addChild("td").addChild("a", format("%s:%s", mut.file,
                mut.sloc.line)).href = toLinkPath(mut.file, mut.stId);
        r.addChild("td", mut.prio.get.to!string);
        r.addChild("td", toString(mut.exitStatus));
        r.addChild("td", mut.killedByTestCases.to!string);
        r.addChild("td", mut.mutant.status == Mutation.Status.unknown ? "" : mut.tested.toShortDate);
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
                    pathToHtmlLink(mut.file)), mut.stId);
            r.addChild("td", mutst.updated.toString);
            r.addChild("td", mutst.prio.get.to!string);
        }
    }
}
