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

    auto ts = TimeScalePointGraph("ScoreHistory");

    const history = reportMutationScoreHistory(db).rollingAvg;
    if (history.data.length > 2 && history.estimate.x != SysTime.init) {
        foreach (v; history.data) {
            ts.put("Score", TimeScalePointGraph.Point(v.timeStamp, v.score.get));
        }
        ts.setColor("Score", "blue");

        ts.put("Trend", TimeScalePointGraph.Point(history.estimate.x, history.estimate.avg));
        ts.put("Trend", TimeScalePointGraph.Point(history.data[$ - 1].timeStamp,
                history.data[$ - 1].score.get));
        ts.put("Trend", TimeScalePointGraph.Point(history.estimate.predX,
                history.estimate.predScore));
        ts.setColor("Trend", () {
            final switch (history.estimate.trend) with (MutationScoreHistory.Trend) {
            case undecided:
                return "grey";
            case negative:
                return "red";
            case positive:
                return "green";
            }
        }());

        ts.html(base, TimeScalePointGraph.Width(80));
        base.addChild("p")
            .appendHtml(
                    "<i>trend</i> is a prediction of how the mutation score will change based on previous scores.");
    }

    addFileCodeChangeGraph(db, doc, base);
    addFileScoreJsVar(db, doc, base);
}

private:

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
    generatePopupHelp(info, "Code change is a graph where the point's X values is the date when the tests were ran and the Y values is the lowest FileScore on that date. If you hover a point you can see all the FileScores on that date.");

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
