#!/usr/bin/env rdmd

import std.stdio;
import std.process;

int main(string[] args) {
    const root = environment.get("ROOT");

    if (root is null) {
        writeln("$ROOT not set");
        return 1;
    }

    return spawnProcess(["git", "clone", "--depth", "1", "-b", "sqlite_src",
            "--single-branch", "https://github.com/joakim-brannstrom/dextool.git", "sqlite_src"])
        .wait;
}
