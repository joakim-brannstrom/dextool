/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.trend;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Element, Link, RawSource, Document;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.report.analyzers : reportTrendByCodeChange,
    reportMutationScoreHistory, MutationScoreHistory;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.backend.report.html.utility : generatePopupHelp;
import dextool.plugin.mutate.backend.report.html.tmpl : TimeScalePointGraph;

void makeTrend(ref Database db, string tag, Document doc, Element root) @trusted {
    import std.datetime : SysTime;

    DashboardCss.h2(root.addChild(new Link(tag, null)).setAttribute("id", tag[1 .. $]), "Trend");

    auto base = root.addChild("div");

    addTrendGraph(db, doc, base);
    addFileCodeChangeGraph(db, doc, base);
    addFileScoreJsVar(db, doc, base);
}

private:

void addTrendGraph(ref Database db, Document doc, Element root) {
    import std.conv : to;

    const history = reportMutationScoreHistory(db);
    if (history.data.length < 2)
        return;

    auto ts = TimeScalePointGraph("ScoreHistory");
    foreach (v; history.rollingAvg(MutationScoreHistory.avgLong).data)
        ts.put("Score" ~ MutationScoreHistory.avgLong.to!string,
                TimeScalePointGraph.Point(v.timeStamp, v.score.get));
    ts.setColor("Score" ~ MutationScoreHistory.avgLong.to!string, "darkblue");
    foreach (v; history.rollingAvg(MutationScoreHistory.avgShort).data)
        ts.put("Score" ~ MutationScoreHistory.avgShort.to!string,
                TimeScalePointGraph.Point(v.timeStamp, v.score.get));
    ts.setColor("Score" ~ MutationScoreHistory.avgShort.to!string, "blue");

    ts.html(root, TimeScalePointGraph.Width(80));

    generatePopupHelp(root.addChild("div", "ScoreX"),
            "The rolling mean where X is the days it is calculated over."
            ~ " Useful to see a trend of the test suite over a short and long term. "
            ~ "If e.g. the long term is starting to go down then it may be time to react."
            ~ " 'Has our teams methodology for how we work with tests degenerated?'");
}

void addFileCodeChangeGraph(ref Database db, Document doc, Element root) {
    import std.algorithm : sort, joiner;
    import std.array : array, appender;
    import std.range : only;
    import std.utf : toUTF8;
    import my.set : Set;
    import my.path : Path;

    const codeChange = reportTrendByCodeChange(db);
    if (codeChange.empty)
        return;

    root.addChild("script").appendChild(new RawSource(doc,
            `// Triggered every time a point is hovered on the ScoreByCodeChange graph
const change = (tooltipItems) => {
    // Convert the X value to the date format that is used in the file_graph_score_data variable
    var date = tooltipItems[0].xLabel.replace("T", " ");
    date = date.substring(0,5) + toMonthShort(date.substring(5,7)) + date.substring(date.length - 13);

    var scoreList = {};
    // Key = file_path, Value = {date : file_score}
    for(const [key, value] of Object.entries(file_graph_score_data)){
        if(value[date] != undefined){
            scoreList[key] = value[date];
        }
    }

    // Format the string that is shown
    var result = "";
    var i = 0;
    var len = Object.keys(scoreList).length;
    for(const [key, value] of Object.entries(scoreList)){
        result += key + " : " + value;
        i += 1;
        if (i < len){
            result += "\n";
        }
    };

    return result;
};
`));

    auto ts = TimeScalePointGraph("ScoreByCodeChange");
    foreach (v; codeChange.sample.byKeyValue.array.sort!((a, b) => a.key < b.key)) {
        ts.put("Lowest score", TimeScalePointGraph.Point(v.key, v.value.min));
    }
    ts.setColor("Lowest score", "purple");
    ts.html(root, TimeScalePointGraph.Width(80),
            "ScoreByCodeChangeData['options']['tooltips']['callbacks'] = {footer:change};");

    auto info = root.addChild("div", "Code change");
    generatePopupHelp(info,
            "The graph is intended to help understand why the overall mutation score have changed (up/down). "
            ~ "It may help locate the files that resulted in the change. "
            ~ "Along the x-axis is the day when the file mutation score where last changed."
            ~ " Multiple files that are changed on the same day are grouped together. "
            ~ "The lowest score among the files changed for the day is plotted on the y-axis.");

    Set!Path pathIsInit;
    auto filesData = appender!(string[])();
    filesData.put("var file_graph_score_data = {};");

    auto scoreData = appender!(string[])();

    foreach (fileScore; codeChange.sample.byKeyValue) {
        foreach (score; fileScore.value.points) {
            if (score.file !in pathIsInit) {
                filesData.put(format!"file_graph_score_data['%s'] = {};"(score.file));
                pathIsInit.add(score.file);
            }

            scoreData.put(format("file_graph_score_data['%s']['%s'] = %.3f;",
                    score.file, fileScore.key, score.value));
        }
    }

    root.addChild("script").appendChild(new RawSource(doc, only(filesData.data,
            scoreData.data).joiner.joiner("\n").toUTF8));
}

void addFileScoreJsVar(ref Database db, Document doc, Element root) {
    import std.algorithm : sort, joiner;
    import std.array : array, appender;
    import std.range : only;
    import std.utf : toUTF8;
    import miniorm : spinSql;
    import my.set : Set;
    import my.path : Path;

    Set!Path pathIsInit;
    auto filesData = appender!(string[])();
    filesData.put("var file_score_data = {};");

    auto scoreData = appender!(string[])();

    foreach (score; spinSql!(() => db.fileApi.getFileScoreHistory)) {
        if (score.file !in pathIsInit) {
            filesData.put(format!"file_score_data['%s'] = {};"(score.file));
            pathIsInit.add(score.file);
        }

        scoreData.put(format("file_score_data['%s']['%s'] = %s;", score.file,
                score.timeStamp, score.score.get));
    }

    root.addChild("script").appendChild(new RawSource(doc, only(filesData.data,
            scoreData.data).joiner.joiner("\n").toUTF8));

}
