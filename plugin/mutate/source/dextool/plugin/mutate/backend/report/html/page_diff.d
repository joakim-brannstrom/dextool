/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_diff;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table;
import my.from_;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.report.analyzers : DiffReport, reportDiff;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, filesCss, tmplDefaultTable;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;

string makeDiffView(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds,
        ref Diff diff, from.my.path.AbsolutePath workdir) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage.filesCss;
    doc.title(format("Diff View %(%s %) %s", humanReadableKinds, Clock.currTime));

    toHtml(reportDiff(db, kinds, diff, workdir), doc.mainBody);

    return doc.toPrettyString;
}

private:

void toHtml(DiffReport report, Element root) {
    import std.array : array;
    import std.conv : to;
    import std.path : buildPath;
    import std.range : repeat;
    import arsd.dom : RawSource;
    import dextool.plugin.mutate.backend.mutation_type : toUser;

    void renderRawDiff(Element root, Diff.Line[] lines) {
        import std.algorithm : countUntil, max;
        import std.string : strip;
        import std.uni : isWhite;

        auto hunk = root.addChild("p");
        uint prev = lines.length != 0 ? lines[0].line : 0;

        foreach (line; lines) {
            if (line.line > prev + 1) {
                hunk = root.addChild("p");
            }

            auto s = hunk.addChild("span");
            auto begin = 0;
            const first_ch = line.text.length != 0 ? line.text[0] : typeof(line.text[0]).init;
            switch (first_ch) {
            case '+':
                s.setAttribute("class", "diff_add");
                begin = 1;
                break;
            case '-':
                s.setAttribute("class", "diff_del");
                begin = 1;
                break;
            default:
            }

            auto txt = line.text[begin .. $];
            const spaces = max(0, txt.countUntil!(a => !a.isWhite) - begin);
            s.addChild(new RawSource(root.parentDocument, format("%s:%s%-(%s%)",
                    line.line, first_ch, "&nbsp;".repeat(spaces))));
            s.appendText(txt.strip);
            s.addChild("br");

            prev = line.line;
        }
    }

    void renderFiles() {
        import std.algorithm : sort, map;
        import std.typecons : tuple;

        with (root.addChild("p")) {
            appendText("This are the mutants for the modified lines.");
            appendText(" ");
            addChild("span", "Red").addClass("diff_del");
            appendText(" removed line.");
            appendText(" ");
            addChild("span", "Green").addClass("diff_add");
            appendText(" added line.");
        }

        auto tbl = tmplDefaultTable(root, ["Analyzed Diff", "Alive", "Killed"]);

        foreach (const pkv; report.files
                .byKeyValue
                .map!(a => tuple(a.key, a.value.dup))
                .array
                .sort!((a, b) => a[1] < b[1])) {
            const path = report.files[pkv[0]];
            tbl.appendRow(tbl.td(path).setAttribute("colspan", "3")
                    .setAttribute("style", "vertical-align:top"));

            auto r = tbl.appendRow();

            if (auto v = pkv[0] in report.rawDiff)
                renderRawDiff(r.addChild("td"), *v);
            else
                continue;

            auto alive_ids = r.addChild("td").setAttribute("style", "vertical-align:top");
            if (auto alive = pkv[0] in report.alive) {
                foreach (a; (*alive).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                    auto link = alive_ids.addChild("a", format("%s:%s",
                            a.kind.toUser, a.sloc.line));
                    link.href = format("%s#%s", buildPath(Html.fileDir,
                            pathToHtmlLink(path)), a.id);
                    alive_ids.appendText(" ");
                }
            }

            auto killed_ids = r.addChild("td").setAttribute("style", "vertical-align:top");
            if (auto killed = pkv[0] in report.killed) {
                foreach (a; (*killed).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                    auto link = killed_ids.addChild("a", format("%s:%s",
                            a.kind.toUser, a.sloc.line));
                    link.href = format("%s#%s", buildPath(Html.fileDir,
                            pathToHtmlLink(path)), a.id);
                    killed_ids.appendText(" ");
                }
            }
        }
    }

    void renderTestCases() {
        root.addChild("p", "This are the test cases that killed mutants in the code changes.")
            .appendText(format("%s test case(s) affected by the change", report.testCases.length));

        auto tc_tbl = tmplDefaultTable(root, ["Test Case"]);
        foreach (tc; report.testCases) {
            tc_tbl.appendRow(tc.name);
        }
    }

    root.addChild("h2", "Diff View");
    root.addChild("p").appendHtml(format("Mutation Score <b>%.3s</b>", report.score));

    root.addChild("h3", "File(s) Report");
    renderFiles();

    root.addChild("h3", "Test Case(s) Report");
    renderTestCases();
}
