/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool_test.compiler;

import std.algorithm : filter, canFind, map, joiner;
import std.array : array;
import std.datetime : dur;
import std.file : exists;
import std.path : baseName;
import std.process : escapeShellFileName, execute;
import std.stdio : writeln;

import dextool_test.builders;
import dextool_test.types;
import dextool_test.utils : TestEnv, makeCommand;

immutable defaultBinary = "./binary";

/** Construct an execution of a compiler.
 */
auto makeCompile(const ref TestEnv testEnv, string compiler) {
    // dfmt off
    return BuildCommandRun(compiler, testEnv.outdir)
        .commandInOutdir(false)
        .addArg("-g")
        .addInclude(testEnv.outdir);
    // dfmt on
}

/// Use in conjunction with makeCompile to setup the default binary destination.
auto outputToDefaultBinary(BuildCommandRun br) {
    return br.addArg(["-o", (br.workdir ~ defaultBinary).toString]);
}

/** Add recursively all files in outdir with extension ext (including dot)
 *
 * Params:
 * br = builder param to extend
 * ext = extension of the files to match (including dot)
 * exclude = files to exclude
 */
auto addFilesFromOutdirWithExtension(BuildCommandRun br, string ext, string[] exclude = null) {
    import dextool_test.utils : recursiveFilesWithExtension;

    foreach (a; recursiveFilesWithExtension(br.workdir, ext).filter!(a => !canFind(exclude,
            a.baseName))) {
        br.addArg(a);
    }

    return br;
}

/// Add parameters to link and use gmock/gtest.
auto addGtestArgs(BuildCommandRun br) {
    // dfmt off
    return br
        .addInclude("fused_gmock")
        .addArg("-L.")
        .addArg("-lgmock_gtest")
        .addArg("-lpthread");
    // dfmt on
}

/// Add the parameter as an include (-I).
auto addInclude(BuildCommandRun br, Path p) {
    return br.addArg(["-I", p.toString]);
}

auto addInclude(BuildCommandRun br, string p) {
    return br.addArg(["-I", p]);
}

auto addInclude(BuildCommandRun br, string[] p) {
    return br.addArg(p.map!(a => ["-I", a]).joiner.array);
}

/// Add the parameter as a define (-D).
auto addDefine(BuildCommandRun br, string v) {
    return br.addArg(["-D", v]);
}

string[] compilerFlags() {
    import proc;

    auto default_flags = ["-std=c++98"];

    auto p = pipeProcess(["g++", "-dumpversion"]).scopeKill;
    auto output = p.process.drainByLineCopy(1.dur!"hours").array;
    if (p.wait != 0) {
        throw new Exception("Failed inspecting the compiler version with g++ -dumpversion");
    }

    if (output.length == 0 || output[0].length == 0) {
        return default_flags;
    } else if (output[0][0] == '5') {
        return default_flags ~ ["-Wpedantic", "-Werror"];
    }

    return default_flags ~ ["-pedantic", "-Werror"];
}

deprecated("legacy function, to be removed") void testWithGTest(const Path[] src,
        const Path binary, const ref TestEnv testEnv, const string[] flags, const string[] incls) {
    immutable bool[string] rm_flag = [
        "-Wpedantic" : true, "-Werror" : true, "-pedantic" : true
    ];

    auto flags_ = flags.filter!(a => a !in rm_flag).array();

    string[] args;
    args ~= "g++";
    args ~= flags_.dup;
    args ~= "-g";
    args ~= ["-o", binary.toString];
    args ~= ["-I", testEnv.outdir.toString];
    args ~= "-I" ~ "fused_gmock";
    args ~= incls.dup;
    args ~= src.map!(a => a.toString).array;
    args ~= "-l" ~ "gmock_gtest";
    args ~= "-lpthread";
    args ~= "-L.";

    execute(args).output.writeln;
}

deprecated("legacy function, to be removed") void compileResult(const Path input, const Path binary,
        const Path main, const ref TestEnv testEnv, const string[] flags, const string[] incls) {
    string[] args;
    args ~= "g++";
    args ~= flags.dup;
    args ~= "-g";
    args ~= ["-o", binary.toString];
    args ~= ["-I", testEnv.outdir.toString];
    args ~= incls.dup;
    args ~= main.toString;

    if (exists(input.toString)) {
        args ~= input.toString;
    }

    execute(args).output.writeln;
}
