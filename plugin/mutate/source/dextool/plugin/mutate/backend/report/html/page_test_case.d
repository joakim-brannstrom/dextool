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
import std.datetime : Clock, dur, SysTime;
import std.format : format;
import std.path : buildPath;
import std.range : enumerate;
import std.stdio : File;
import std.traits : EnumMembers;

import arsd.dom : Element, RawSource, Link, Document, Table;
import my.optional;
import my.path : AbsolutePath;
import my.set;

import dextool.plugin.mutate.backend.database : Database, spinSql, MutationId,
    TestCaseId, MutationStatusId, MutantInfo2;
import dextool.plugin.mutate.backend.report.analyzers : reportTestCaseUniqueness,
    TestCaseUniqueness, reportTestCaseSimilarityAnalyse,
    TestCaseSimilarityAnalyse, TestCaseClassifier, makeTestCaseClassifier, TestCaseMetadata;
import dextool.plugin.mutate.backend.report.html.constants : HtmlStyle = Html, DashboardCss;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    dashboardCss, tmplSortableTable, tmplDefaultTable;
import dextool.plugin.mutate.backend.report.html.utility : pathToHtmlLink, toShortDate;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.type : Mutation, toString, TestCase;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportSection;

@safe:

void makeTestCases(ref Database db, string tag, Element root, ref const ConfigReport conf,
        const(Mutation.Kind)[] kinds, TestCaseMetadata metaData, AbsolutePath testCasesDir) @trusted {
    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]),
            "Test Cases");
    auto sections = conf.reportSection.toSet;

    ReportData data;

    if (ReportSection.tc_similarity in sections)
        data.similaritiesData = reportTestCaseSimilarityAnalyse(db, kinds, 5);

    data.addSuggestion = ReportSection.tc_suggestion in sections;
    // 10 is magic number. feels good.
    data.classifier = makeTestCaseClassifier(db, 10);

    const tabGroupName = "testcase_class";
    Element[Classification] tabLink;

    { // tab links
        auto tab = root.addChild("div").addClass("tab");
        foreach (class_; [EnumMembers!Classification]) {
            auto b = tab.addChild("button").addClass("tablinks")
                .addClass("tablinks_" ~ tabGroupName);
            b.setAttribute("onclick", format!`openTab(event, '%s', '%s')`(class_, tabGroupName));
            b.appendText(class_.to!string);
            tabLink[class_] = b;
        }
    }

    Table[Classification] tabContent;
    foreach (a; [EnumMembers!Classification]) {
        auto div = root.addChild("div").addClass("tabcontent")
            .addClass("tabcontent_" ~ tabGroupName).setAttribute("id", a.to!string);
        if (a == Classification.Redundant)
            div.addChild("p", format(classDescription[a], data.classifier.threshold));
        else
            div.addChild("p", classDescription[a]);
        tabContent[a] = tmplSortableTable(div, ["Name", "Tests", "Killed"]);
    }

    auto newTestCases = spinSql!(() => db.testCaseApi.getNewTestCases).toSet;
    logger.trace("new test cases ", newTestCases);
    long[Classification] classCnt;
    foreach (tcId; spinSql!(() => db.testCaseApi.getDetectedTestCaseIds)) {
        const name = spinSql!(() => db.testCaseApi.getTestCaseName(tcId));

        auto reportFname = name.pathToHtmlLink;
        auto fout = File(testCasesDir ~ reportFname, "w");
        TestCaseSummary summary;
        spinSql!(() {
            // do all the heavy database interaction in a transaction to
            // speedup by reduce locking.
            auto t = db.transaction;
            makeTestCasePage(db, kinds, name, tcId, (data.similaritiesData is null)
                ? null : data.similaritiesData.similarities.get(tcId, null),
                data, metaData, summary, fout);
        });

        auto classification = classify(TestCase(name), summary, data.classifier, metaData);
        if (classification == Classification.Buggy && tcId in newTestCases) {
            logger.trace("test case is new and tagged as buggy: ", name);
            // only report test cases as buggy if all alive mutants have been
            // tested. it is only then we can be sure that they actually are buggy.
        } else {
            classCnt[classification] += 1;

            auto r = tabContent[classification].appendRow;
            {
                auto td = r.addChild("td");
                td.addChild("a", name).href = buildPath(HtmlStyle.testCaseDir, reportFname);
            }
            r.addChild("td", summary.score.to!string);
            r.addChild("td", summary.kills.to!string);
        }
    }

    foreach (a; classCnt.byKeyValue) {
        tabLink[a.key].appendText(format!" %s"(a.value));
        if (auto c = a.key in classColor)
            tabLink[a.key].style = *c;
    }
}

private:

enum Classification {
    Unique,
    Redundant,
    Buggy,
    Normal
}

immutable string[Classification] classDescription;
immutable string[Classification] classColor;

shared static this() @trusted {
    classDescription = cast(immutable)[
        Classification.Unique: "kills mutants that no other test case do.",
        Classification.Redundant: "all mutants the test case kill are also killed by %s other test cases. The test case is probably redudant and thus can be removed.",
        Classification.Buggy: "zero killed mutants. The test case is most probably incorrect. Immediatly inspect the test case.",
        Classification.Normal: ""
    ];

    classColor = cast(immutable)[
        // light green
        Classification.Unique: "background-color: #b3ff99",
        // light orange
        Classification.Redundant: "background-color: #ffc266",
        // light red
        Classification.Buggy: "background-color: #ff9980"
    ];
}

Classification classify(TestCase tc, const TestCaseSummary summary,
        const ref TestCaseClassifier tclass, const ref TestCaseMetadata metaData) {
    if (summary.kills == 0)
        return Classification.Buggy;
    if (summary.score == 1)
        return Classification.Unique;

    if (auto v = tc in metaData.redundant) {
        if (*v)
            return Classification.Redundant;
    } else if (summary.score >= tclass.threshold)
        return Classification.Redundant;

    return Classification.Normal;
}

struct ReportData {
    TestCaseSimilarityAnalyse similaritiesData;
    TestCaseClassifier classifier;

    bool addSuggestion;
}

struct TestCaseSummary {
    long kills;

    // min(f) where f is the number of test cases that killed a mutant.
    // thus if a test case have one unique mutant the score is 1, none then it
    // is the lowest of all mutant test case kills.
    long score;
}

void makeTestCasePage(ref Database db, const(Mutation.Kind)[] kinds, const string name,
        const TestCaseId tcId, TestCaseSimilarityAnalyse.Similarity[] similarities,
        const ReportData rdata, TestCaseMetadata metaData, ref TestCaseSummary summary, ref File out_) @system {
    import std.path : baseName;
    import dextool.plugin.mutate.backend.type : TestCase;

    auto doc = tmplBasicPage.dashboardCss;
    scope (success)
        out_.write(doc.toPrettyString);

    doc.title(format("%s %s", name, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");
    doc.root.childElements("head")[0].addChild("script").addChild(new RawSource(doc, jsIndex));

    doc.mainBody.addChild("h1").appendText(name);
    if (auto v = TestCase(name) in metaData.loc) {
        auto p = doc.mainBody.addChild("p");
        p.addChild("a", v.file.baseName).href = v.file;
        if (v.line.hasValue)
            p.appendText(" at line " ~ v.line.orElse(0u).to!string);
    }
    if (auto v = TestCase(name) in metaData.text)
        doc.mainBody.addChild(new RawSource(doc, *v));

    doc.mainBody.addChild("h2").appendText("Killed");
    addKilledMutants(db, kinds, tcId, rdata, summary, doc.mainBody);

    if (!similarities.empty) {
        doc.mainBody.addChild("h2").appendText("Similarity");
        addSimilarity(db, similarities, doc.mainBody);
    }
}

void addKilledMutants(ref Database db, const(Mutation.Kind)[] kinds,
        const TestCaseId tcId, const ReportData rdata, ref TestCaseSummary summary, Element root) @system {
    import std.algorithm : min;

    auto kills = db.testCaseApi.testCaseKilledSrcMutants(kinds, tcId);
    summary.kills = kills.length;
    summary.score = kills.length == 0 ? 0 : long.max;

    auto uniqueElem = root.addChild("div");

    {
        auto p = root.addChild("p");
        p.addChild("b", "TestCases");
        p.appendText(": number of test cases that kill the mutant.");
    }
    {
        auto p = root.addChild("p");
        p.addChild("b", "Suggestion");
        p.appendText(": alive mutants on the same source code location. Because they are close to a mutant that this test case killed it may be suitable to extend this test case to also kill the suggested mutant.");
    }

    auto tbl = tmplSortableTable(root, ["Link", "TestCases"] ~ (rdata.addSuggestion
            ? ["Suggestion"] : null) ~ ["Priority", "ExitCode", "Tested"]);

    foreach (const id; kills.sort) {
        auto r = tbl.appendRow();

        const info = db.mutantApi.getMutantInfo(id).orElse(MutantInfo2.init);

        r.addChild("td").addChild("a", format("%s:%s", info.file,
                info.sloc.line)).href = format("%s#%s", buildPath("..",
                HtmlStyle.fileDir, pathToHtmlLink(info.file)), info.id.get);

        summary.score = min(info.tcKilled, summary.score);
        {
            auto td = r.addChild("td", info.tcKilled.to!string);
            if (info.tcKilled == 1) {
                td.style = "background-color: lightgreen";
            }
        }

        if (rdata.addSuggestion) {
            auto tds = r.addChild("td");
            foreach (s; db.mutantApi.getSurroundingAliveMutants(id).enumerate) {
                // column sort in the html report do not work correctly if starting from 0.
                auto td = tds.addChild("a", format("%s", s.index + 1));
                td.href = format("%s#%s", buildPath("..", HtmlStyle.fileDir,
                        pathToHtmlLink(info.file)), db.mutantApi.getMutationId(s.value).get);
                td.appendText(" ");
            }
        }

        r.addChild("td", info.prio.get.to!string);
        r.addChild("td", toString(info.exitStatus));
        r.addChild("td", info.updated.toShortDate);
    }
}

void addSimilarity(ref Database db, TestCaseSimilarityAnalyse.Similarity[] similarities,
        Element root) @system {
    import dextool.cachetools;

    auto getPath = nullableCache!(MutationStatusId, string, (MutationStatusId id) {
        auto path = spinSql!(() => db.mutantApi.getPath(id)).get;
        auto mutId = spinSql!(() => db.mutantApi.getMutationId(id)).get;
        return format!"%s#%s"(buildPath("..", HtmlStyle.fileDir, pathToHtmlLink(path)), mutId.get);
    })(0, 30.dur!"seconds");

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
