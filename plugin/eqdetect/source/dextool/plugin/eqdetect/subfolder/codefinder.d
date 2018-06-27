/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

kommentar
*/
module dextool.plugin.eqdetect.subfolder.codefinder;

struct ForFinder {
    void search(string filename){
        import std.stdio : writeln, File;
        import std.algorithm : canFind;
        import std.conv : to;

        File file = File(filename, "r");
        int i = 1;

        while (!file.eof()) {
            string s = file.readln();
            if(canFind(s, "for") && !canFind(s, "//")){
                writeln(to!string(i) ~ s);
            }
            i++;
        }

        file.close();
    }
}
