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

import arsd.dom : Element, Table, RawSource;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : MutationScoreHistory,
    reportMutationScoreHistory;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.js;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

string makeScoreHistory(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import dextool.plugin.mutate.type : ReportSection;
    import my.set;

    auto sections = conf.reportSection.toSet;

    auto doc = tmplBasicPage;
    doc.title(format("Mutation Score History %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.setAttribute("onload", "init()");

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, js_index));

    toHtml(reportMutationScoreHistory(db), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(const MutationScoreHistory history, Element root) {
    import std.conv : to;
    import std.typecons : tuple;
    import std.datetime : DateTime, Date;

    auto base = root.addChild("div").addClass("base");

    auto heading = base.addChild("h2").addClass("tbl_header");
    heading.addChild("i").addClass("right");
    heading.appendText(" History");

    auto tbl = tmplDefaultTable(base.addChild("div").addClass("tbl_container"), [
            "Date", "Score"
            ]);
    foreach (score; history.pretty) {
        tbl.appendRow((cast(DateTime) score.timeStamp).date.toString,
                format!"%.3s"(score.score.get));
    }
}
