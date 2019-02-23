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

    const dextool_build = environment.get("DEXTOOL_BUILD");
    const dextool_job = environment.get("DEXTOOL_JOB");

    switch (dextool_job) {
    case "build":
        build(env, root, dextool_build);
        break;
    case "test":
        test(env, root, dextool_build);
        break;
    default:
        writeln("$DEXTOOL_JOB not set");
        return 1;
    }

    return 0;
}

void build(string[string] env, string root, string dextool_build) {
    const jobs = totalCPUs.to!string;
    mkdir("build");

    switch (dextool_build) {
    case "DebugCov":
        chdir("build");
        run([
                "cmake", "-DTEST_WITH_COV=ON", "-DCMAKE_BUILD_TYPE=Debug",
                "-DBUILD_TEST=ON", ".."
                ]);
        run(["make", "all", "-j", jobs], env);
        break;
    case "Debug":
        chdir("build");
        run(["cmake", "-DCMAKE_BUILD_TYPE=Debug", "-DBUILD_TEST=ON", ".."]);
        run(["make", "all", "-j", jobs], env);
        break;
    case "Release":
        // Assuming that if the tests pass for Debug build they also pass for Release.
        chdir("build");
        const build_doc = environment.get("BUILD_DOC");
        run([
                "cmake", "-DBUILD_DOC=" ~ build_doc is null ? "OFF" : build_doc,
                "-DCMAKE_INSTALL_PREFIX=" ~ buildPath(root,
                    "test_install_of_dextool"), "-DCMAKE_BUILD_TYPE=Release", ".."
                ]);
        run(["make", "all", "-j", jobs], env);
        break;
    default:
        writeln("$DEXTOOL_BUILD not set");
        throw new Exception("fail");
    }
}

void test(string[string] env, string root, string dextool_build) {
    const jobs = totalCPUs.to!string;
    const dc = environment.get("DC");

    switch (dextool_build) {
    case "DebugCov":
        chdir("build");
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
        run(["make", "check", "-j", jobs], env);
        run(["make", "check_integration", "-j", jobs], env);
        chdir(root);
        break;
    case "Release":
        // Assuming that if the tests pass for Debug build they also pass for Release.
        chdir("build");
        run(["make", "all", "-j", jobs], env);
        // Testing the install target because it has had problems before
        run(["make", "install"], env);
        chdir(root);
        run(["./tools/travis_test_install.sh"]);
        break;
    default:
        writeln("$DEXTOOL_BUILD not set");
        throw new Exception("fail");
    }
}

void run(string[] cmd, string[string] env = null) {
    import std.format;

    writefln("run: %-(%s %)", cmd);
    if (spawnProcess(cmd, env).wait != 0)
        throw new Exception(format("Command failed: %-(%s %)", cmd));
}
