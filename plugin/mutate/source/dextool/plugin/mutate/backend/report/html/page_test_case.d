/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_test_case;

import logger = std.experimental.logger;
import std.algorithm : sort;
import std.array : empty;
import std.conv : to;
import std.datetime : Clock, dur;
import std.format : format;
import std.path : buildPath;
import std.stdio : File;

import arsd.dom : Element, RawSource, Link, Document;
import my.path : AbsolutePath;
import my.set;

import dextool.plugin.mutate.backend.database : Database, spinSql, MutationId,
    TestCaseId, MutationStatusId;
import dextool.plugin.mutate.backend.report.analyzers : reportTestCaseUniqueness,
    TestCaseUniqueness, reportTestCaseSimilarityAnalyse, TestCaseSimilarityAnalyse;
import dextool.plugin.mutate.backend.report.html.constants : HtmlStyle = Html, DashboardCss;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    dashboardCss, tmplSortableTable, tmplDefaultTable;
import dextool.plugin.mutate.backend.report.html.utility : pathToHtml;
import dextool.plugin.mutate.backend.report.html.utility : pathToHtmlLink;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportSection;
import dextool.cachetools;

void makeTestCases(ref Database db, ref const ConfigReport conf, const(MutationKind)[] humanReadableKinds,
        const(Mutation.Kind)[] kinds, AbsolutePath testCasesDir, string tag, Element root) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]),
            "Test Cases");
    auto sections = conf.reportSection.toSet;

    ReportData data;

    if (ReportSection.tc_unique in sections) {
        data.addUnique = true;
        data.uniqueData = reportTestCaseUniqueness(db, kinds);
    }

    if (ReportSection.tc_similarity in sections)
        data.similaritiesData = reportTestCaseSimilarityAnalyse(db, kinds, 5);

    data.addSuggestion = ReportSection.tc_suggestion in sections;

    auto tbl = tmplSortableTable(root, ["Name", "Score", "Killed"] ~ data.columns);
    {
        auto p = root.addChild("p");
        p.addChild("b", "Is Unique");
        p.appendText(": a test case that has killed some mutants that no other test case has.");
    }
    root.addChild("p", "A test case that has zero killed mutants has a high probability of containing implementation errors. They should be manually inspected.");

    const total = spinSql!(() => db.totalSrcMutants(kinds)).count;
    foreach (tcId; spinSql!(() => db.testCaseApi.getDetectedTestCaseIds)) {
        auto r = tbl.appendRow;

        const name = spinSql!(() => db.testCaseApi.getTestCaseName(tcId));
        const kills = spinSql!(() => db.testCaseApi.getTestCaseInfo(tcId, kinds)).killedMutants;
        const ratio = 100.0 * ((total == 0) ? 0.0 : (cast(double) kills / total));

        auto reportFname = name.pathToHtmlLink;
        auto fout = File(testCasesDir ~ reportFname, "w");
        spinSql!(() {
            // do all the heavy database interaction in a transaction to
            // speedup to reduce locking.
            auto t = db.transaction;
            makeTestCasePage(db, humanReadableKinds, kinds, name, tcId,
                data.uniqueData.uniqueKills.get(tcId, null), (data.similaritiesData is null)
                ? null : data.similaritiesData.similarities.get(tcId, null),
                data.addSuggestion, fout);
        });

        r.addChild("td").addChild("a", name).href = buildPath(HtmlStyle.testCaseDir, reportFname);
        r.addChild("td", format!"%.1f"(ratio));
        r.addChild("td", kills.to!string);
        if (data.addUnique)
            r.addChild("td", (tcId in data.uniqueData.uniqueKills ? "x" : ""));

        if (kills == 0)
            r.style = "background-color: lightred";
    }
}

private:

struct ReportData {
    string[] columns() @safe pure nothrow const {
        return (addUnique ? ["Is Unique"] : null);
    }

    bool addUnique;
    TestCaseUniqueness uniqueData;

    TestCaseSimilarityAnalyse similaritiesData;

    bool addSuggestion;
}

void makeTestCasePage(ref Database db, const(MutationKind)[] humanReadableKinds,
        const(Mutation.Kind)[] kinds, const string name, const TestCaseId tcId, MutationStatusId[] unique,
        TestCaseSimilarityAnalyse.Similarity[] similarities, const bool addSuggestion, ref File out_) {
    auto doc = tmplBasicPage.dashboardCss;
    scope (success)
        out_.write(doc.toPrettyString);

    auto getPath = nullableCache!(MutationStatusId, string, (MutationStatusId id) {
        auto path = spinSql!(() => db.getPath(id)).get;
        auto mutId = spinSql!(() => db.getMutationId(id)).get;
        return format!"%s#%s"(buildPath("..", HtmlStyle.fileDir, pathToHtmlLink(path)), mutId.get);
    })(0, 30.dur!"seconds");

    doc.title(format("Test Case %s %(%s %) %s", name, humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");
    doc.root.childElements("head")[0].addChild("script").addChild(new RawSource(doc, jsIndex));

    doc.mainBody.addChild("h2").appendText("Killed");
    addKilledMutants(db, kinds, tcId, unique, addSuggestion, getPath, doc.mainBody);

    if (!similarities.empty) {
        doc.mainBody.addChild("h2").appendText("Similarity");
        addSimilarity(db, similarities, getPath, doc.mainBody);
    }
}

void addKilledMutants(PathCacheT)(ref Database db, const(Mutation.Kind)[] kinds, const TestCaseId tcId,
        MutationStatusId[] uniqueKills, const bool addSuggestion, ref PathCacheT getPath,
        Element root) {
    auto kills = db.testCaseApi.testCaseKilledSrcMutants(kinds, tcId);
    auto unique = uniqueKills.toSet;

    auto tbl = tmplSortableTable(root, ["Link", "Tested", "Priority"] ~ (uniqueKills.empty
            ? null : ["Unique"]) ~ (addSuggestion ? ["Suggestion"] : null));
    {
        auto p = root.addChild("p");
        p.addChild("b", "Unique");
        p.appendText(": only this test case kill the mutant.");
    }
    {
        auto p = root.addChild("p");
        p.addChild("b", "Suggestion");
        p.appendText(": alive mutants on the same source code location. Because they are close to a mutant that this test case killed it may be suitable to extend this test case to also kill the suggested mutant.");
    }

    foreach (const id; kills.sort) {
        auto r = tbl.appendRow();

        const mutId = db.getMutationId(id).get;
        auto mut = db.getMutation(mutId).get;
        auto mutStatus = db.getMutationStatus2(id);

        r.addChild("td").addChild("a", format("%s:%s", mut.file,
                mut.sloc.line)).href = format("%s#%s", buildPath("..",
                HtmlStyle.fileDir, pathToHtmlLink(mut.file)), mut.id.get);
        r.addChild("td", mutStatus.updated.toString);
        r.addChild("td", mutStatus.prio.get.to!string);

        if (!uniqueKills.empty)
            r.addChild("td", (id in unique ? "x" : ""));

        if (addSuggestion) {
            auto tds = r.addChild("td");
            foreach (s; db.getSurroundingAliveMutants(id)) {
                tds.addChild("a", format("%s", s.get)).href = format("%s#%s",
                        buildPath("..", HtmlStyle.fileDir, pathToHtmlLink(mut.file)),
                        db.getMutationId(s).get);
            }
        }
    }
}

void addSimilarity(PathCacheT)(ref Database db,
        TestCaseSimilarityAnalyse.Similarity[] similarities, ref PathCacheT getPath, Element root) {
    root.addChild("p", "How similary this test case is to others.");
    {
        auto p = root.addChild("p");
        p.addChild("b", "Note");
        p.appendText(": The analysis is based on the mutants that the test cases kill; thus, it is dependent on the mutation operators that are used when generating the report.");

        root.addChild("p", "The intersection column is the mutants that are killed by both the current test case and in the column Test Case.")
            .appendText(
                    " The difference column are the mutants that are only killed by the current test case.");
    }

    auto tbl = tmplDefaultTable(root, [
            "Test Case", "Similarity", "Difference", "Intersection"
            ]);
    foreach (const sim; similarities) {
        auto r = tbl.appendRow();

        const name = db.testCaseApi.getTestCaseName(sim.testCase);
        r.addChild("td").addChild("a", name).href = buildPath(name.pathToHtmlLink);

        r.addChild("td", format("%#.3s", sim.similarity));

        auto difference = r.addChild("td");
        foreach (const mut; sim.difference) {
            auto link = difference.addChild("a", mut.to!string);
            link.href = getPath(mut).get;
            difference.appendText(" ");
        }

        auto s = r.addChild("td");
        foreach (const mut; sim.intersection) {
            auto link = s.addChild("a", mut.to!string);
            link.href = getPath(mut).get;
            s.appendText(" ");
        }
    }
}
