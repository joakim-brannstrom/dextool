/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_short_term_view;

import logger = std.experimental.logger;
import std.algorithm : sort, map, filter, count;
import std.conv : to;
import std.datetime : Clock, dur;
import std.format : format;
import std.typecons : tuple;
import std.xml : encode;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.nodes;
import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

@safe:

auto makeShortTermView(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds,
        ref Diff diff, AbsolutePath workdir) {
    import dextool.plugin.mutate.backend.report.html.tmpl : addStateTableCss;

    auto root = defaultHtml(format("Short Term View %(%s %) %s",
            humanReadableKinds, Clock.currTime));
    auto s = root.preambleBody.n("style".Tag);
    addStateTableCss(s);
    s.put(".diff_del {background-color: lightpink;}");
    s.put(".diff_add {background-color: lightgreen;}");

    toHtml(reportDiff(db, kinds, diff, workdir), root.body_);

    return root;
}

private:

void toHtml(DiffReport report, HtmlNode root) {
    import std.array : array;
    import std.path : buildPath;
    import std.range : enumerate, repeat;
    import dextool.plugin.mutate.backend.mutation_type : toUser;

    void renderRawDiff(HtmlNode root, Diff.Line[] lines) {
        import std.algorithm : countUntil, max;
        import std.string : strip;
        import std.uni : isWhite;

        auto hunk = root.n("p".Tag);
        uint prev = lines.length != 0 ? lines[0].line : 0;

        foreach (line; lines) {
            if (line.line > prev + 1) {
                hunk = root.n("p".Tag);
            }

            auto s = hunk.n("span".Tag);
            auto begin = 0;
            const first_ch = line.text.length != 0 ? line.text[0] : typeof(line.text[0]).init;
            switch (first_ch) {
            case '+':
                s.putAttr("class", "diff_add");
                begin = 1;
                break;
            case '-':
                s.putAttr("class", "diff_del");
                begin = 1;
                break;
            default:
            }

            auto txt = line.text[begin .. $];
            const spaces = max(0, txt.countUntil!(a => !a.isWhite) - begin);
            txt = format("%s:%s%-(%s%)%s", line.line, first_ch,
                    "&nbsp;".repeat(spaces), txt.strip.encode);
            s.put(txt);
            s.put("<br>");

            prev = line.line;
        }
    }

    void renderFiles() {
        with (root.n("p".Tag)) {
            put("This are the mutants for the modified lines.");
            n("span".Tag).putAttr("class", "diff_del").put("Red");
            n("id".Tag).put(" removed line.");
            n("span".Tag).putAttr("class", "diff_add").put("Green");
            n("id".Tag).put(" added line.");
        }

        auto tbl = HtmlTable.make;
        root.put(tbl.root);
        tbl.root.putAttr("class", "overlap_tbl");
        foreach (c; ["Analyzed Diff", "Alive", "Killed"])
            tbl.putColumn(c).putAttr("class", tableColumnHdrStyle);

        foreach (const pkv; report.files
                .byKeyValue
                .map!(a => tuple(a.key, a.value.dup))
                .array
                .sort!((a, b) => a[1] < b[1])) {
            const path = report.files[pkv[0]];
            tbl.newRow.td.putAttr("colspan", "3").putAttr("valign", "top").put(path);

            auto r = tbl.newRow;

            if (auto v = pkv[0] in report.rawDiff)
                renderRawDiff(r.td, *v);

            auto alive_ids = r.td.putAttr("valign", "top");
            if (auto alive = pkv[0] in report.alive) {
                foreach (a; (*alive).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                    alive_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                            format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                    alive_ids.put(" ");
                }
            }

            auto killed_ids = r.td.putAttr("valign", "top");
            if (auto killed = pkv[0] in report.killed) {
                foreach (a; (*killed).dup.sort!((a, b) => a.sloc.line < b.sloc.line)) {
                    killed_ids.put(aHref(buildPath(htmlFileDir, pathToHtmlLink(path)),
                            format("%s:%s", a.kind.toUser, a.sloc.line), a.id.to!string));
                    killed_ids.put(" ");
                }
            }
        }
    }

    void renderTestCases() {
        root.n("p".Tag).put("This are the test cases that killed mutants in the code changes.")
            .put(format("%s test case(s) affected by the change", report.testCases.length));

        auto tc_tbl = HtmlTable.make;
        root.put(tc_tbl.root);
        tc_tbl.root.putAttr("class", "overlap_tbl");
        tc_tbl.putColumn("Test Case").putAttr("class", tableColumnHdrStyle);
        foreach (tc; report.testCases) {
            auto r = tc_tbl.newRow;
            r.td.put(tc.name);
        }
    }

    root.n("h2".Tag).put("Short Term View");
    root.n("p".Tag).put("Mutation Score: ").put(report.score.to!string);

    root.n("h3".Tag).put("File(s) Report");
    renderFiles();

    root.n("h3".Tag).put("Test Case(s) Report");
    renderTestCases();
}
