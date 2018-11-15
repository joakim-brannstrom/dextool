/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file writes the generated code into a file with a name according to the plugin
standard. The user will provide what code to write to the file and what filetype it is
(_source_, _mutant_ or _klee_).

*/

module dextool.plugin.eqdetect.backend.filewriter;
import dextool.type : FileName;

@safe:

void writeToFile(string text, FileName filename) {
    import std.stdio : File;
    import std.file : mkdirRecurse;

    auto dir = "eqdetect_generated_files";
    dir.mkdirRecurse;

    import std.path : buildPath;
    string path = buildPath(dir, filename);

    auto file = File(path, "w");
    file.write(text);
}
