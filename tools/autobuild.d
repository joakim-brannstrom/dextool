#!/usr/bin/env dub
/+ dub.sdl:
    name "autobuild"
+/

import std.process;

int main(string[] args) {
    // run the script from the root of the Dextool repo
    const AUTOBUILD_TOOL = "tools/autobuild";
    const AUTOBUILD_BIN = "autobuild.bin";

    if (spawnProcess(["dub", "build", "--skip-registry=all", "-b", "release"],
            null, Config.none, AUTOBUILD_TOOL).wait != 0) {
        return 1;
    }

    args = () {
        if (args.length > 1)
            return args[1 .. $];
        return null;
    }();

    return spawnProcess(["./.autobuild.bin"] ~ args).wait;
}
