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

Document tmplBasicPage() @trusted {
    auto doc = new Document(`<html lang="en">
<head><meta http-equiv="Content-Type" content="text/html;charset=UTF-8"></head>
<body></body>
</html>
`);
    return doc;
}

/// Add the CSS style after the head element.
Document dashboardCss(Document doc) @trusted {
    //import dextool.plugin.mutate.backend.resource : tmplDefaultCss;
    import arsd.dom : RawSource;
    import dextool.plugin.mutate.backend.resource : dashboard, jsIndex;

    auto data = dashboard();

    auto style = doc.root.childElements("head")[0].addChild("style");
    style.addChild(new RawSource(doc, data.bootstrapCss.get));
    style.addChild(new RawSource(doc, data.dashboardCss.get));

    return doc;
}

Document filesCss(Document doc) @trusted {
    import dextool.plugin.mutate.backend.resource : tmplDefaultCss;

    auto style = doc.root.childElements("head")[0].addChild("style");
    style.appendText(tmplDefaultCss);

    return doc;
}

Table tmplDefaultTable(Element n, string[] header) @trusted {
    import std.range : enumerate;
    import std.format : format;
    import dextool.plugin.mutate.backend.report.html.constants : TableStyle = Table;

    auto tbl = n.addChild("table").require!Table;
    tbl.addClass(TableStyle.style);

    auto tr = n.parentDocument.createElement("tr");
    foreach (h; header.enumerate) {
        auto th = tr.addChild("th", h.value);
        th.addClass(TableStyle.hdrStyle);
        th.setAttribute("id", format!"col-%s"(h.index));
        th.appendText(" ");
        th.addChild("i").addClass("right");
    }

    tbl.addChild("thead").appendChild(tr);

    return tbl;
}

Table tmplDefaultMatrixTable(Element n, string[] header) @trusted {
    import dextool.plugin.mutate.backend.report.html.constants;

    auto tbl = n.addChild("table").require!Table;
    tbl.addClass(MatrixTable.style);

    auto tr = n.parentDocument.createElement("tr");
    foreach (h; header) {
        auto th = tr.addChild("th", h);
        th.addClass(MatrixTable.hdrStyle);
    }

    tbl.addChild("thead").appendChild(tr);

    return tbl;
}
