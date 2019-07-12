/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
import std.file : thisExePath;
import std.path;
import std.process;
import std.stdio : writefln;

int main(string[] args) {
    const dargs = () {
        if (args.length > 1)
            return args[1 .. $];
        return null;
    }();

    auto cmd = [buildPath(thisExePath.dirName, "bin", "dextool")] ~ dargs;
    writefln("%-(%s %)", cmd);

    return spawnProcess(cmd).wait;
}
