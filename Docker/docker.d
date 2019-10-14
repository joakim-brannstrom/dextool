#!/usr/bin/env dub
/+ dub.sdl:
    name "docker"
+/
/*
This program constructs a bundle of Dockerfiles from those in "partial/".

How the Dockerfiles are used is not intended to be a generic solution thus the
flow is hard coded for dextools specific needs.

Exceptions are used as a lazy way to signal that the build failed.
*/
import logger = std.experimental.logger;
import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.exception;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.range;
import std.stdio;
import std.string;
import std.traits;
static import std.getopt;

int main(string[] args) {
    bool doCleanup;
    string testGroup;
    // dfmt off
    std.getopt.getopt(args, std.getopt.config.passThrough, std.getopt.config.keepEndOfOptions,
            "cleanup", "remove all created images", &doCleanup,
            "group", "group of tests to run", &testGroup);
    // dfmt on

    Tag tag;
    scope (exit)
        if (doCleanup)
            tag.cleanup;

    const buildType = environment.get("DEXTOOL_BUILD");
    const job = environment.get("DEXTOOL_JOB");

    const tarName = "dextool_to_docker.tar.gz".absolutePath;
    prepareTarBall(tarName);
    scope (exit)
        remove(tarName);

    alias TestFn = void delegate();
    TestFn[][string] tests;

    // dextool officially supports CentOS and Ubuntu with LDC and DMD.
    //
    // Assumption:
    // * if the test cases passes on ubuntu it means that they will pass on
    // CentOS too with a very high probability.
    // * the dub integration relies on cmake. By testing cmake for enough
    // targets by itself it means that the only thing to test with dub is that
    // it integrats with cmake correctly and installs the binaries on the
    // expected location so `dub run` works.
    //
    // Test strategy:
    // * test minimal requirements for ubuntu, both compilers.
    // * test latest dmd for ubuntu with dub integration. This also tests the release build.
    // * release build for centos7 with minimal compiler

    // Setup tests
    tests["ldc-ubuntu-min-test"] ~= () {
        build(mergeFiles([
                    "ubuntu_minimal_base", "ldc_min_version", "ldc",
                    "fix_repo", "prepare_test_build_ubuntu", "build_test"
                ]), tag.next);
    };
    tests["dmd-ubuntu-min-test"] ~= () {
        build(mergeFiles([
                    "ubuntu_minimal_base", "dmd_min_version", "dmd",
                    "fix_repo", "prepare_test_build_ubuntu", "build_test"
                ]), tag.next);
    };
    tests["dmd-ubuntu-latest-test"] ~= () {
        build(mergeFiles([
                    "ubuntu_latest_base", "dmd_latest_version", "dmd",
                    "fix_repo", "prepare_test_build_ubuntu", "build_test"
                ]), tag.next);
    };
    tests["dmd-ubuntu-latest-release"] ~= () {
        build(mergeFiles([
                    "ubuntu_latest_base", "dmd_latest_version", "dmd", "fix_repo",
                    "prepare_release_build_ubuntu", "build_release", "examples"
                ]), tag.next);
    };
    tests["dmd-ubuntu-latest-dub"] ~= () {
        build(mergeFiles([
                    "ubuntu_latest_base", "dmd_latest_version", "dmd",
                    "fix_repo", "build_with_dub"
                ]), tag.next);
    };
    tests["dmd-centos7-min-release"] ~= () {
        build(mergeFiles([
                    "centos7_base", "dmd_min_version", "dmd", "fix_repo",
                    "prepare_release_build_centos7", "build_release"
                ]), tag.next);
    };

    if (testGroup.empty) {
        foreach (f; tests.byValue.joiner)
            f();
    } else if (auto tg = testGroup in tests) {
        foreach (f; *tg)
            f();
    } else {
        writefln("No such test group %s. Valid groups are %s", testGroup, tests.byKey);
        return 1;
    }

    return 0;
}

void prepareTarBall(string tarName) {
    const gitRoot = execute(["git", "rev-parse", "--git-dir"]).output.dirName.absolutePath;
    spawnProcess(["git", "archive", "-o", tarName, "HEAD"], null, Config.none, gitRoot).wait;
}

/// Build a docker image.
void build(string dockerFile, string tag) {
    if (spawnProcess([
                "docker", "image", "build", "-f", dockerFile, "-t", tag, "."
            ]).wait != 0)
        throw new Exception("Failed building " ~ dockerFile ~ " " ~ tag);
}

/// Merge `src` into one file with the filename as the return value.
string mergeFiles(string[] src) {
    const dst = "docker." ~ src.join('.');
    auto fout = File(dst, "w");
    foreach (s; src.map!(a => buildPath(__FILE_FULL_PATH__.dirName, "partial", a))) {
        fout.writeln("# ", s.baseName);
        fout.write(readText(s));
        fout.writeln;
    }

    return dst;
}

/// Automatic incremented tag number.
struct Tag {
    ulong id;
    string[] tags;

    string next() {
        tags ~= format("dextool_ci_test%s", id++);
        return tags[$ - 1];
    }

    void cleanup() {
        foreach (n; tags)
            removeImage(n);
    }
}

void removeImage(string name) {
    spawnProcess(["docker", "image", "rm", name]).wait;
}
