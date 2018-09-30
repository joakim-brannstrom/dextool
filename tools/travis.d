#!/usr/bin/env dub
/+ dub.sdl:
    name "travis"
+/

import std.algorithm;
import std.conv;
import std.file;
import std.parallelism;
import std.path;
import std.process;
import std.stdio;

int main(string[] args) {
    auto root = getcwd;
    auto env = ["ROOT" : root, "VERBOSE" : "1"];
    const dc = environment.get("DC");

    if (!dc.among("dmd", "ldc2")) {
        writefln("Compiler (%s) not set or supported", dc);
        return 1;
    }

    run(["./tools/travis_install_dep.d"], env);
    const sqlite3 = "-L " ~ root ~ "/sqlite_src -lsqlite3";
    const jobs = totalCPUs.to!string;

    const dextool_build = environment.get("DEXTOOL_BUILD");

    mkdir("build");

    switch (dextool_build) {
    case "DebugCov":
        chdir("build");
        run(["cmake", "-DTEST_WITH_COV=ON", "-DCMAKE_BUILD_TYPE=Debug",
                "-DBUILD_TEST=ON", "-DSQLITE3_LIB=" ~ sqlite3, ".."]);
        run(["make", "all", "-j", jobs], env);
        run(["make", "check", "-j", jobs], env);
        run(["make", "check_integration", "-j", jobs], env);
        chdir(root);

        if (dc == "dmd") {
            // The coverage files are copied to the project root to allow codecov to find
            // them.
            spawnShell("cp -- build/coverage/*.lst .").wait;
            spawnShell("bash <(curl -s https://codecov.io/bash)").wait;
        }
        break;
    case "Debug":
        chdir("build");
        run(["cmake", "-DCMAKE_BUILD_TYPE=Debug", "-DBUILD_TEST=ON",
                "-DSQLITE3_LIB=" ~ sqlite3, ".."]);
        run(["make", "all", "-j", jobs], env);
        run(["make", "check", "-j", jobs], env);
        run(["make", "check_integration", "-j", jobs], env);
        chdir(root);
        break;
    case "Release":
        // Assuming that if the tests pass for Debug build they also pass for Release.
        chdir("build");
        const build_doc = environment.get("BUILD_DOC");
        run(["cmake", "-DBUILD_DOC=" ~ build_doc is null ? "OFF" : build_doc, "-DCMAKE_INSTALL_PREFIX=" ~ buildPath(root,
                "test_install_of_dextool"), "-DCMAKE_BUILD_TYPE=Release",
                "-DSQLITE3_LIB=" ~ sqlite3, ".."]);
        run(["make", "all", "-j", jobs], env);
        // Testing the install target because it has had problems before
        run(["make", "install"], env);
        chdir(root);
        run(["./tools/travis_test_install.sh"]);
        break;
    default:
        writeln("$DEXTOOL_BUILD not set");
        return 1;
    }

    return 0;
}

void run(string[] cmd, string[string] env = null) {
    writefln("run: %-(%s %)", cmd);
    if (spawnProcess(cmd, env).wait != 0)
        throw new Exception("Command failed");
}
