/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the functionality for extracting snippets of code from a given cursor
and returns a validated UTF8 string of the extracted code. It also returns the mutated
version of the code extracted.

TODO:
- Do we need try/catch for handling file?
- Make it possible to extract code without generating mutation (userinput?)
*/
module dextool.plugin.eqdetect.subfolder.codegenerator;

import dsrcgen.c;
import clang.Cursor;
import dextool.plugin.eqdetect.subfolder.dbhandler : Mutation;

class SnippetFinder{
    @trusted static string generate(Cursor cursor, CModule generatedCode, Mutation mutation){
        import std.stdio;
        auto file = File(cursor.extent.path, "r");

        import std.file: getSize;
        auto buffer = file.rawRead(new char[getSize(cursor.extent.path)]);
        file.close();

        buffer = buffer[cursor.extent.start.offset .. cursor.extent.end.offset];
        mutation.offset_begin = mutation.offset_begin - cursor.extent.start.offset;
        mutation.offset_end = mutation.offset_end - cursor.extent.start.offset;
        buffer = buffer ~ "\n\n//Mutated code: \n" ~ generateMut(buffer, mutation);

        import std.utf: validate, toUTF8;
        validate(buffer);
        return toUTF8(buffer);
    }

    @trusted static auto generateMut(char[] content, Mutation mutation){
        import dextool.plugin.mutate.backend.generate_mutant: makeMutation;
        import dextool.plugin.mutate.backend.type : Offset;
        import dextool.plugin.mutate.backend.type : mutationStruct = Mutation;

        auto mut = makeMutation(cast(mutationStruct.Kind)mutation.kind, mutation.lang);
        auto temp = content[0 .. mutation.offset_begin];
        temp = temp ~ mut.mutate(content[mutation.offset_begin .. mutation.offset_end]);
        temp = temp ~ content[mutation.offset_end .. content.length];
        return temp;
    }
}
