/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.tmpl;

import arsd.dom : Document, Element, require, Table;

@safe:

immutable tmplIndexStyle = import("source.css");

immutable tmplIndexBody = import("source.html");

Document tmplBasicPage() @trusted {
    auto doc = new Document(`<html lang="en">
<head><meta http-equiv="Content-Type" content="text/html;charset=UTF-8"></head>
<body></body>
</html>
`);
    tmplDefaultCss(doc);
    return doc;
}

/// Add the CSS style after the head element.
void tmplDefaultCss(Document doc) @trusted {
    auto s = doc.root.childElements("head")[0].addChild("style");
    s.appendText(import("default.css"));
}

Table tmplDefaultTable(Element n, string[] header) @trusted {
    import std.algorithm : map;
    import std.array : array;
    import std.range : enumerate;
    import std.format : format;
    import dextool.plugin.mutate.backend.report.html.constants;

    auto tbl = n.addChild("table").require!Table;
    tbl.addClass(tableStyle);

    auto tr = n.parentDocument.createElement("tr");
    foreach (h; header.enumerate) {
        auto th = tr.addChild("th", h.value);
        th.addClass(tableColumnHdrStyle);
        th.setAttribute("id", format("%s-%d", "col", h.index));
    }

    tbl.addChild("thead").appendChild(tr);

    return tbl;
}

Table tmplDefaultMatrixTable(Element n, string[] header) @trusted {
    import std.algorithm : map;
    import std.array : array;
    import dextool.plugin.mutate.backend.report.html.constants;

    auto tbl = n.addChild("table").require!Table;
    tbl.addClass(matrixTableStyle);

    auto tr = n.parentDocument.createElement("tr");
    foreach (h; header) {
        auto th = tr.addChild("th", h);
        th.addClass(matrixTableHdrStyle);
    }

    tbl.addChild("thead").appendChild(tr);

    return tbl;
}
