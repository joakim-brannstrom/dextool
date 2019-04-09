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
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage, tmplDefaultTable;
import dextool.plugin.mutate.backend.report.utility;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind;
import dextool.type : AbsolutePath;

auto makeNomut(ref Database db, ref const ConfigReport conf,
        const(MutationKind)[] humanReadableKinds, const(Mutation.Kind)[] kinds) @trusted {
    import std.datetime : Clock;

    auto doc = tmplBasicPage;
    doc.title(format("NoMut Details %(%s %) %s", humanReadableKinds, Clock.currTime));
    doc.mainBody.addChild("p",
            "This is all the mutation suppressions that are used and affects the analysis.");

    db.getMutantationMetaData(kinds, Mutation.Status.alive).toHtml(db, doc.mainBody);

    return doc.toPrettyString;
}

private:

// TODO: this is very inefficient implementation. There are so many lookups in
// the database. It "works" as long as there are only a limited amount of
// nomut.
void toHtml(MutantMetaData[] data, ref Database db, Element root) {
    import std.algorithm : sort;
    import std.array : array, empty;
    import std.path : buildPath;
    import std.typecons : Tuple;
    import std.uni : toLower;
    import sumtype;
    import dextool.plugin.mutate.backend.database : MutationId, NoMetadata, NoMut;
    import dextool.plugin.mutate.backend.report.html.page_files : pathToHtmlLink;

    alias IdComment = Tuple!(MutationId, "id", string, "comment");
    IdComment[][string] tags;

    foreach (x; data) {
        x.attr.match!((NoMetadata a) {}, (NoMut a) {
            tags[a.tag.toLower] ~= IdComment(x.id, a.comment);
        });
    }

    foreach (tag; tags.byKey.array.sort) {
        if (!tag.empty)
            root.addChild("h2", tag);

        auto tbl = tmplDefaultTable(root, ["Mutant"]);
        foreach (m; tags[tag].array.sort!((a, b) => a.comment < b.comment)) {
            auto r = tbl.appendRow();

            auto file = db.getPath(m.id);
            if (file.isNull)
                continue;

            auto td = r.addChild("td");
            td.addChild("a", file.get).href = format("%s#%s",
                    buildPath(htmlFileDir, pathToHtmlLink(file.get)), m.id);
            td.addChild("br");
            td.appendText(m.comment);
        }
    }
}
