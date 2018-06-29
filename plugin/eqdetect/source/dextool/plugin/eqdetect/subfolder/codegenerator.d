/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

TODO:Description of file
*/
module dextool.plugin.eqdetect.subfolder.codegenerator;

import dsrcgen.c;
import clang.Cursor;

class SnippetFinder{
    @trusted static string generate(Cursor cursor, CModule generatedCode){
        import std.stdio;
        auto file = File(cursor.extent.path, "r");

        import std.file: getSize;
        auto buffer = file.rawRead(new char[getSize(cursor.extent.path)]);

        import std.utf: validate, toUTF8;
        buffer = buffer[cursor.extent.start.offset .. cursor.extent.end.offset];

        file.close();

        validate(buffer);
        return toUTF8(buffer);
    }
}
