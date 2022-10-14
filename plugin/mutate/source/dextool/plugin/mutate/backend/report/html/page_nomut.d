/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.page_nomut;

import logger = std.experimental.logger;
import std.format : format;

import arsd.dom : Document, Element, require, Table;

import dextool.plugin.mutate.backend.database : Database, MutantMetaData;
import dextool.plugin.mutate.backend.report.html.constants;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage,
    dashboardCss, tmplDefaultTable;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.type : AbsolutePath;

auto makeNomut(ref Database db, ref const ConfigReport conf) @trusted {
    auto doc = tmplBasicPage.dashboardCss;
    doc.title("NoMut Details");
    doc.mainBody.addChild("h1", "NoMut Details");
    doc.mainBody.addChild("p",
            "This is all the mutation suppressions that are used and affects the analysis.");

    db.mutantApi.getMutantMetaData(Mutation.Status.alive).toHtml(db, doc.mainBody);

    return doc.toPrettyString;
}

private:

// TODO: this is very inefficient implementation. There are so many lookups in
// the database. It "works" as long as there are only a limited amount of
// nomut.
void toHtml(MutantMetaData[] data, ref Database db, Element root) {
    import std.algorithm : sort, map;
    import std.array : array, empty;
    import std.path : buildPath;
    import std.typecons : Tuple;
    import std.uni : toLower;
    import sumtype;
    import dextool.plugin.mutate.backend.database : MutationStatusId, NoMetadata, NoMut;
    import dextool.plugin.mutate.backend.report.html.utility : pathToHtmlLink;

    alias IdComment = Tuple!(MutationStatusId, "id", string, "comment");
    string[MutationStatusId][string] tags;

    // group by the tag that can be added to a nomut via
    // // NOMUT (tag) <comment>
    foreach (x; data) {
        x.attr.match!((NoMetadata a) {}, (NoMut a) {
            if (auto v = a.tag.toLower in tags) {
                (*v)[x.id] = a.comment;
            } else {
                tags[a.tag.toLower] = [x.id: a.comment];
            }
        });
    }

    foreach (tag; tags.byKey.array.sort) {
        if (!tag.empty)
            root.addChild("h2", tag);

        auto tbl = tmplDefaultTable(root, ["Mutant"]);
        foreach (m; tags[tag].byKeyValue
                .map!(a => IdComment(a.key, a.value))
                .array
                .sort!((a, b) => a.comment < b.comment)) {
            auto r = tbl.appendRow();

            auto file = db.mutantApi.getPath(m.id);
            if (file.isNull)
                continue;

            auto td = r.addChild("td");
            td.addChild("a", file.get).href = format("%s#%s",
                    buildPath(Html.fileDir, pathToHtmlLink(file.get)), m.id);
            td.addChild("br");
            td.appendText(m.comment);
        }
    }
}
