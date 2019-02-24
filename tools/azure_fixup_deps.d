#!/usr/bin/env dub
/+ dub.sdl:
    name "travis_install_dep"
+/

import std.algorithm;
import std.array;
import std.ascii;
import std.exception;
import std.process;
import std.range;
import std.stdio;
import std.string;

int main(string[] args) {
    auto env = ["DEBIAN_FRONTEND" : "noninteractive"];

    // has to cleanout llvm-6.X because otherwise we get packet collisions when
    // installing the dev packages
    const pkgs = executeShell("dpkg -l|grep -E 'llvm|clang'|grep -v mono", env)
        .output.splitter(newline).map!(a => a.strip)
        .filter!"!a.empty"
        .map!(a => a.splitter
                .filter!"!a.empty"
                .filter!(a => a.length > 2)
                .dropOne
                .takeOne)
        .joiner
        .array;

    stderr.writeln("Packages to remove: ", pkgs);

    // has to remove all llvm-6.0 packages before installing because of collision
    foreach (const pkg; pkgs) {
        run(["sudo", "apt-get", "-y", "remove", pkg], env).collectException;
    }

    run([
            "sudo", "apt-get", "-y", "install", "libsqlite3-dev",
            "llvm-6.0-dev", "libclang-6.0-dev"
            ], env);

    return 0;
}

void run(string[] cmd, string[string] env = null) {
    import std.format;

    stderr.writefln("run: %-(%s %)", cmd);
    if (spawnProcess(cmd, env).wait != 0)
        throw new Exception(format("Command failed: %-(%s %)", cmd));
}
