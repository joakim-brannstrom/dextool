/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.


*/
module dextool.plugin.eqdetect.subfolder.filewriter;

static void writeToFile(string text_to_write, string base, int kind, int id, bool isMutation){
    import std.stdio : File;
    import std.conv : to;
    import std.path : stripExtension, extension;
    import std.file : mkdirRecurse;
    import dextool.plugin.mutate.backend.type : mutationStruct = Mutation;

    auto dir = "eqdetect_generated_files";
    dir.mkdirRecurse;

    string filename;

    if (!isMutation){
        filename = dir ~ "/" ~ stripExtension(base) ~ "_source_" ~ to!string(id) ~ "_"
        ~ to!string(cast(mutationStruct.Kind)kind) ~ extension(base);
    } else {
        filename = dir ~ "/" ~ stripExtension(base) ~ "_mutation_" ~ to!string(id) ~ "_"
        ~ to!string(cast(mutationStruct.Kind)kind) ~ extension(base);
    }

    auto file = File(filename, "w");
    file.write(text_to_write);
}
