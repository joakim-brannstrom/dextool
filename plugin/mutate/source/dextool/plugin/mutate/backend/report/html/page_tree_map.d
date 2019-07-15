module dextool.plugin.mutate.backend.report.html.page_tree_map;

import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.report.html : FileIndex;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage;

@trusted auto makeTreeMapJSON(FileIndex[] files) {
    import std.stdio : writeln;
    import std.array : array;
    import std.range : enumerate;
    import std.json : JSONValue;
    import std.path : pathSplitter;
    import std.format;

    JSONValue root = ["name" : "root"];
    auto parent = root;
    foreach (f; files) {
        auto path = pathSplitter(f.display);

        segments: foreach (i, seg; path.enumerate) {
            if ("children" in parent) { // Parent has children -> look for segment in children
                for (int j; j < parent["children"].array.length; j++) {
                    auto child = parent["children"][j];
                    
                    if (child["name"].str == seg) {// Segment already added to JSON
                        parent = child; // Update parent
                        continue segments; // Go to next segment
                    }
                }
            } 
            else { // Parent has no children -> init list
                parent.object["children"] = JSONValue[].init;
            }
            
            JSONValue child = ["name": seg]; // Create new child
            parent.object["children"].array ~= child; // Add to parent
            parent = child; // Update parent          
        }

        // Reached final segment -> file. Add score and locs
        parent.object["locs"] = JSONValue(f.totalMutants);
        if (f.totalMutants == 0) {
            parent.object["score"] = JSONValue(1.0);
        } else {
            parent.object["score"] = JSONValue(
                    cast(double) f.killedMutants / cast(double) f.totalMutants);
        }
        parent = root; //Finished with file -> set parent to root.
    }
    return root.toPrettyString;
}

auto makeTreeMapPage(FileIndex[] files) {
    import std.format : format;
    auto doc = tmplBasicPage;

    doc.mainBody.setAttribute("onload", "init()");
    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, import("d3.min.js")));
    auto container = doc.mainBody.addChild("div");
    auto s2 = doc.mainBody.addChild("script");
    s2.addChild(new RawSource(doc, format("const g_indata = %s", makeTreeMapJSON(files))));
    s2.addChild(new RawSource(doc, import("treemap.js")));
    container.setAttribute("id", "container");
    return doc.toPrettyString;
}
