module dextool.plugin.mutate.backend.report.html.page_tree_map;


import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.report.html : FileIndex;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage;
@trusted
auto makeTreeMapJSON(FileIndex[] files) {
    import std.stdio : writeln;
    import std.array : array, split;
    import std.range : enumerate;
    import std.json;
    JSONValue root = ["name":"root"];
    auto curr = root;
    foreach (f; files) {
        auto path = f.display.split("/");
        
        foreach (i, seg; path.enumerate) {
            if ("children" in curr) {
                bool exists = false;
                for (int j; j<curr["children"].array.length; j++) {
                    auto c = curr["children"][j];
                    
                    if ( c["name"].str == seg) {
                        curr = c;
                        exists = true;
                        break;
                    }
                }
                if (exists)
                    continue;
            }
            JSONValue tmp = ["name":seg];
            
            if (i+1==path.length) {
                tmp.object["locs"] = JSONValue(f.totalMutants);
                if (f.totalMutants == 0)
                    tmp.object["score"] = JSONValue(1.0);
                else
                    tmp.object["score"] = JSONValue(cast(double) f.killedMutants / cast(double) f.totalMutants);
            }
            if ("children" !in curr) {
                curr.object["children"] = JSONValue([tmp]);
            }
            else {
                curr.object["children"].array ~= tmp;
            }
            curr = tmp;

        }
        curr = root;
    }
    return root.toPrettyString;
}
auto makeTreeMapPage() {
    auto doc = tmplBasicPage;
    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, import("d3.min.js")));
    auto container = doc.mainBody.addChild("div");
    auto s2 = doc.mainBody.addChild("script");
    s2.addChild(new RawSource(doc, import("treemap.js")));
    container.setAttribute("id", "container");
    return doc.toPrettyString;
}