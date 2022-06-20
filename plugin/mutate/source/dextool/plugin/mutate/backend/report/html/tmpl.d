/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.tmpl;

import std.conv : to;
import std.format : format;
import std.json : JSONValue;

import arsd.dom : Document, Element, require, Table, RawSource;
import my.named_type;

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
    import dextool.plugin.mutate.backend.resource : dashboard, jsIndex, tmplDefaultCss;

    auto data = dashboard();

    auto style = doc.root.childElements("head")[0].addChild("style");
    style.addChild(new RawSource(doc, data.bootstrapCss.get));
    style.addChild(new RawSource(doc, data.dashboardCss.get));
    style.addChild(new RawSource(doc, tmplDefaultCss));

    return doc;
}

Document filesCss(Document doc) @trusted {
    import dextool.plugin.mutate.backend.resource : tmplDefaultCss;

    auto style = doc.root.childElements("head")[0].addChild("style");
    style.appendText(tmplDefaultCss);

    return doc;
}

Table tmplDefaultTable(Element n, string[] header) @trusted {
    auto base = tmplTable(n);

    auto tr = base.div.parentDocument.createElement("tr");
    foreach (h; header) {
        tr.addChild("th", h);
    }

    base.tbl.addChild("thead").appendChild(tr);
    return base.tbl;
}

Table tmplSortableTable(Element n, string[] header) @trusted {
    import std.range : enumerate;
    import std.format : format;
    import dextool.plugin.mutate.backend.report.html.constants : DashboardCss;

    auto base = tmplTable(n);
    DashboardCss.sortableTableDiv(base.div);
    DashboardCss.sortableTable(base.tbl);

    auto tr = base.div.parentDocument.createElement("tr");
    foreach (h; header.enumerate) {
        auto th = tr.addChild("th", h.value);
        DashboardCss.sortableTableCol(th).setAttribute("id",
                format!"col-%s"(h.index)).appendText(" ").addChild("i").addClass("right");
    }

    base.tbl.addChild("thead").appendChild(tr);
    return base.tbl;
}

private struct TableData {
    Element div;
    Table tbl;
}

private TableData tmplTable(Element n) @trusted {
    import dextool.plugin.mutate.backend.report.html.constants : DashboardCss;

    auto div = n.addChild("div");
    auto tbl = div.addChild("table").require!Table;
    DashboardCss.defaultTable(tbl);

    return TableData(div, tbl);
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

struct PieGraph {
    alias Width = NamedType!(long, Tag!"PieGraphWidth", long.init, TagStringable);
    static struct Item {
        string label;
        string color;
        double value;
    }

    /// Name of the chart
    string name;

    /// Containted items.
    Item[] items;

    string data() {
        import std.algorithm : map;
        import std.array : array;

        JSONValue j;
        j["type"] = "pie";
        j["data"] = () {
            JSONValue data_;

            data_["datasets"] = [
                () {
                    JSONValue d;
                    d["data"] = items.map!(a => a.value).array;
                    d["backgroundColor"] = items.map!(a => a.color).array;
                    d["label"] = name;
                    return d;
                }()
            ];

            data_["options"] = () {
                JSONValue d;
                JSONValue tooltips;
                tooltips["enable"] = true;
                d["tooltips"] = tooltips;
                return d;
            }();

            data_["labels"] = items.map!(a => a.label).array;
            return data_;
        }();

        return format!"var %1$sData = %2$s;"(name, j.toString);
    }

    Element canvas(const Width w) @trusted {
        auto root = new Element("div", ["style": format!"width:%s%%"(w.get)]);
        root.addChild(new Element("canvas", ["id": name]));
        return root;
    }

    /// Call to initialize the graph with data.
    string initCall() @trusted {
        return format!"var ctx%1$s = document.getElementById('%1$s').getContext('2d');\nvar chart%1$s = new Chart(ctx%1$s, %1$sData);\n"(
                name);
    }

    void html(Element root, const Width w) @trusted {
        root.addChild(canvas(w));
        root.addChild("script").innerRawSource(data ~ initCall);
    }
}

struct TimeScalePointGraph {
    import std.datetime : SysTime;

    alias Width = NamedType!(long, Tag!"PieGraphWidth", long.init, TagStringable);
    static struct Point {
        SysTime x;
        double value;
    }

    static struct Sample {
        Point[] values;
        string bgColor;
    }

    /// Name of the chart
    string name;

    /// The key is the sample name.
    Sample[string] samples;

    this(string name) {
        this.name = name;
    }

    void setColor(string sample, string c) {
        samples.update(sample, { return Sample(null, c); }, (ref Sample s) {
            s.bgColor = c;
        });
    }

    void put(string sample, Point p) {
        samples.update(sample, { return Sample([p], "blue"); }, (ref Sample s) {
            s.values ~= p;
        });
    }

    string data() {
        import std.algorithm : map;
        import std.array : array, appender;

        JSONValue j;
        j["type"] = "line";
        j["data"] = () {
            JSONValue data_;
            data_["datasets"] = () {
                auto app = appender!(JSONValue[])();
                foreach (sample; samples.byKeyValue) {
                    JSONValue d;
                    d["label"] = sample.key;
                    d["backgroundColor"] = sample.value.bgColor;
                    d["borderColor"] = sample.value.bgColor;
                    d["fill"] = false;
                    auto data = appender!(JSONValue[])();
                    foreach (v; sample.value.values) {
                        JSONValue tmp;
                        tmp["x"] = v.x.toISOExtString;
                        tmp["y"] = v.value;
                        data.put(tmp);
                    }
                    d["data"] = data.data;
                    app.put(d);
                }
                return app.data;
            }();

            return data_;
        }();

        j["options"] = () {
            JSONValue d;
            d["title"] = () {
                JSONValue tmp;
                tmp["display"] = true;
                tmp["text"] = name;
                return tmp;
            }();

            d["tooltips"] = () { JSONValue tmp; tmp["enable"] = true; return tmp; }();

            d["scales"] = () {
                JSONValue x;
                x["type"] = "time";
                x["display"] = true;
                x["scaleLabel"] = ["display": "true", "labelString": "Date"];
                x["ticks"] = ["major": ["fontStyle": "bold"]];

                JSONValue y;
                y["display"] = true;
                y["scaleLabel"] = ["display": "true", "labelString": "value"];

                JSONValue tmp;
                tmp["xAxes"] = [x];
                tmp["yAxes"] = [y];
                return tmp;
            }();

            return d;
        }();

        return format!"var %1$sData = %2$s;"(name, j.toString);
    }

    Element canvas(const Width w) @trusted {
        auto root = new Element("div", ["style": format!"width:%s%%"(w.get)]);
        root.addChild(new Element("canvas", ["id": name]));
        return root;
    }

    /// Call to initialize the graph with data.
    string initCall() @trusted {
        return format!"var ctx%1$s = document.getElementById('%1$s').getContext('2d');\nvar chart%1$s = new Chart(ctx%1$s, %1$sData);\n"(
                name);
    }

    void html(Element root, const Width w) @trusted {
        root.addChild(canvas(w));
        root.addChild("script").innerRawSource(data ~ initCall);
    }
}
