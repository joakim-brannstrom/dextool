#!/usr/bin/env dub
/+ dub.sdl:
    name "preprocess_libclang"
+/
import std;

int main(string[] args) {
    if (args.length < 5) {
        writefln("Usage: %s SRC_PATH DST_PATH <compiler flags>", args[0]);
        writeln("SRC_PATH - path to libclang headers such as Index.h");
        writeln("DST_PATH - where to write the preprocessed headers");
        writeln("<compiler flags> - flags needed to preprocess headers such as -I");
        return 1;
    }

    const src = args[1];
    const dst = buildPath(args[2], "clang/c");
    const dstHdr = buildPath(args[2], "clang-c");
    const flags = args[3 .. $];

    mkdirRecurse(dst);
    mkdirRecurse(dstHdr);

    writeln("Processing libclang headers");
    foreach (hdr; dirEntries(src, SpanMode.shallow).filter!(a => a.extension == ".h")) {
        writeln("  ", hdr.name);
        auto content = readText(hdr.name);
        File(buildPath(dst, hdr.name.baseName.setExtension(".c")), "w").writeln(content);
        File(buildPath(dstHdr, hdr.name.baseName.setExtension(".h")), "w").writeln(content);
    }

    return 0;
}
