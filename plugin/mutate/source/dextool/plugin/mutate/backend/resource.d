/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.resource;

import my.resource;
import my.path;
import my.optional;

@safe:

private string[string] cacheData;

private string readData(string r) @safe {
    import logger = std.experimental.logger;
    import std.path : buildPath;

    if (auto v = r in cacheData) {
        return *v;
    }

    const p = buildPath("mutate", r);
    auto rfile = resolve(dataSearch("dextool"), Path(p));
    if (rfile.hasValue) {
        auto txt = readResource(rfile.orElse(ResourceFile(AbsolutePath(r))));
        cacheData[r] = txt;
        return txt;
    }

    logger.error("Unable to read resource ", p);
    throw new Exception("Unable to read resource " ~ p);
}

string jsTableOnClick() {
    return readData("table_on_click.js");
}

string jsIndex() {
    return readData("index.js");
}

string jsSource() {
    return readData("source.js");
}

string jsScoreHistory() {
    return readData("score_history.js");
}

string jsTreeMap() {
    return readData("treemap.js");
}

string jsD3Mini() {
    return readData("d3.min.js");
}

string tmplIndexStyle() {
    return readData("source.css");
}

string tmplIndexBody() {
    return readData("source.html");
}

string tmplDefaultCss() {
    return readData("default.css");
}

string schemataHeader() {
    return readData("schemata_header.h");
}

string schemataImpl() {
    return readData("schemata_header.c");
}

string coverageMapHdr() {
    return readData("coverage_mmap.h");
}

string coverageMapImpl() {
    return readData("coverage_mmap.c");
}
