/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.constants;

import arsd.dom : Element;

struct Html {
    static immutable ext = ".html";
    static immutable dir = "html";
    static immutable fileDir = "files";
}

// CSS style

struct TableStat {
    static immutable style = "stat_tbl";
}

struct Table {
    static immutable hdrStyle = "tg-g59y";
    static immutable rowStyle = "tg-0lax";
    static immutable rowDarkStyle = "tg-0lax_dark";
}

struct MatrixTable {
    static immutable style = "vertical_tbl";
    static immutable hdrStyle = "tg";
}

struct DashboardCss {
    static Element h2(Element root, string txt) @trusted {
        return root.addChild("h2", txt).addClass("sub-header");
    }

    static Element defaultTable(Element root) @trusted {
        return root.addClass("table table-striped");
    }

    static Element sortableTableDiv(Element root) @trusted {
        return root.addClass("table-sortable-div");
    }

    static Element sortableTable(Element root) @trusted {
        return root.addClass("table-sortable");
    }

    static Element sortableTableCol(Element root) @trusted {
        return root.addClass("table-col-sortable");
    }
}
