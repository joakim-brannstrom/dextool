/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file parses the result which KLEE has produced in the earlier steps. As it is implemted now,
KLEE generates a result.txt file which contains the information needed by mutation_handler.
ErrorTextParser interprets these result by splitting the read string into pieces and returns
a ErrorResult-struct defined in type.d.

TODO:
- Change name to resultTextParser, since that is what the parser does
*/

module dextool.plugin.eqdetect.backend.parser;

import dextool.plugin.eqdetect.backend.type : ErrorResult;

@safe:

static ErrorResult errorTextParser(string filepath) {
    ErrorResult errorResult;
    try {
        import std.stdio : File;
        import std.file : getSize;

        auto file = File(filepath, "r");
        auto s = file.rawRead(new char[getSize(filepath)]);

        import std.string : split;

        errorResult.status = s.split(":")[0];
        if (errorResult.status == "Assert" || errorResult.status == "Abort") {
            import std.algorithm.iteration : splitter;
            import std.range : dropOne;

            foreach (data; s.splitter("data: ").dropOne) { //first element does not contain data
                errorResult.inputdata = errorResult.inputdata ~ data.split(" ")[0];
            }
        }
        return errorResult;
    } catch (Exception e) {
        import std.experimental.logger;

        warning(e.msg);
        return errorResult;
    }
}
