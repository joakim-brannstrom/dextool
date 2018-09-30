#!/usr/bin/env dub
/+ dub.sdl:
    name "symlink"
+/

import std.stdio;
import std.file;

int main(string[] args) {
    if (args.length != 3) {
        writeln("Wrong number of arguments: src dst");
        return 1;
    }

    auto src = args[1];
    auto dst = args[2];

    if (exists(dst))
        remove(dst);
    std.file.symlink(src, dst);

    return 0;
}
