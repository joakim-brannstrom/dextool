#!/usr/bin/env rdmd
/**
Date: 2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Setup a build directory for development.
*/
module dev_setup;

import std;

immutable sourcePaths = ["libs", "plugin", "source"];

int main(string[] args) {
    if (!exists("build")) {
        mkdir("build");
    }

    if (spawnProcess([
                "cmake", "-DCMAKE_BUILD_TYPE=Debug", "-DBUILD_TEST=ON", ".."
            ], null, std.process.Config.none, "build").wait != 0)
        return 1;

    spawnProcess(["dscanner", "--sloc"] ~ sourcePaths).wait;

    writeln("To rebuild on changes run:");
    writeln(`dub run watchexec -- -w libs -w plugin -w source --shell -- "export CPUNR=$(nproc);cd build;make check -j \$CPUNR && make -j \$CPUNR && make check_integration -j \$CPUNR"`);

    return 0;
}
