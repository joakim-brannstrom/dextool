#!/usr/bin/env dub
/+ dub.sdl:
    name "symlink"
+/
import std.file : symlink, remove, exists, mkdirRecurse;
import std.path : dirName;
import std.stdio : writeln;

int main(string[] args) {
    if (args.length != 3) {
        writeln("Wrong number of arguments: src dst");
        return 1;
    }

    auto src = args[1];
    auto dst = args[2];

    if (!exists(dst.dirName)) {
        mkdirRecurse(dst.dirName);
    }

    if (exists(dst)) {
        remove(dst);
    }
    symlink(src, dst);

    return 0;
}
