/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_score_history;

import logger = std.experimental.logger;
import std.datetime : Clock, dur;
import std.format : format;

import arsd.dom : Document, Element, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MutationScoreHistory,
    reportMutationScoreHistory;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.resource;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable, filesCss;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

string makeScoreHistory(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import dextool.plugin.mutate.type : ReportSection;
    import my.set;

    auto sections = conf.reportSection.toSet;

    auto doc = tmplBasicPage.filesCss;
    doc.title(format("Mutation Score History %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init();make_chart(g_data);");

    auto script = doc.root.childElements("head")[0].addChild("script");
    script.addChild(new RawSource(doc, jsIndex));
    script.addChild(new RawSource(doc, jsScoreHistory));

    toHtml(reportMutationScoreHistory(db), doc, doc.mainBody, script);

    script.addChild(new RawSource(doc, jsD3Mini));
    script.appendText("\n");

    return doc.toPrettyString;
}

private:

void toHtml(const MutationScoreHistory history, Document doc, Element root, Element script) {
    import std.array : appender;
    import std.conv : to;
    import std.datetime : DateTime, Date;
    import std.json : JSONValue;
    import std.range : retro;
    import std.typecons : tuple;

    auto base = root.addChild("div").addClass("base");

    auto heading = base.addChild("h2").addClass("tbl_header");
    heading.addChild("i").addClass("right");
    heading.appendText(" History");

    base.addChild("div").setAttribute("id", "chart");

    auto tbl = tmplDefaultTable(base.addChild("div").addClass("tbl_container"), [
            "Date", "Score"
            ]);
    auto app = appender!(JSONValue[])();
    foreach (score; history.pretty.retro) {
        const date = (cast(DateTime) score.timeStamp).date.toString;
        tbl.appendRow(date, format!"%.3s"(score.score.get));

        JSONValue v;
        v["name"] = date;
        v["value"] = score.score.get;
        app.put(v);
    }

    script.addChild(new RawSource(doc, format!"const g_data = %s;\n"(app.data)));
}
