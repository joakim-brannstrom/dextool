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

class CodeGenerator{
    import std.stdio;
    @safe static void generate(Cursor[] children, CModule generatedCode){
        foreach(Cursor c ; children){
            writeln(c);
        }
    }
}
