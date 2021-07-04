/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.utility;

import std.datetime : SysTime;

import dextool.plugin.mutate.backend.report.html.constants;
import dextool.type : Path;

@safe:

/// Convert a file path to a html represented path.
string pathToHtml(string p) {
    import std.algorithm : joiner;
    import std.path : pathSplitter, buildPath;
    import std.utf : toUTF8;

    return p.pathSplitter.joiner("__").toUTF8;
}

Path pathToHtmlLink(string p) {
    return Path(pathToHtml(p) ~ Html.ext);
}

string toShortDate(SysTime ts) {
    import std.format : format;

    return format("%04s-%02s-%02s", ts.year, cast(ushort) ts.month, ts.day);
}
