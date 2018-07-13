/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.


*/
module dextool.plugin.eqdetect.backend.filewriter;
import dextool.type : FileName;

@safe:

static FileName writeToFile(string text_to_write, string base, int kind, int id, string filetype) {
    import std.stdio : File, writeln;
    import std.conv : to;
    import std.path : stripExtension, extension, baseName;
    import std.file : mkdirRecurse;
    import dextool.plugin.mutate.backend.type : mutationStruct = Mutation;

    auto dir = "eqdetect_generated_files";
    dir.mkdirRecurse;

    FileName filename;

    filename = stripExtension(base) ~ filetype ~ to!string(id) ~ "_" ~ to!string(
            cast(mutationStruct.Kind) kind) ~ extension(base);

    import std.path : buildPath;

    string path = buildPath(dir, filename);
    auto file = File(path, "w");
    file.write(text_to_write);
    return filename;
}
