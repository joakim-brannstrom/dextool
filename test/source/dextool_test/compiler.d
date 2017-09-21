/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool_test.compiler;

import scriptlike;

import dextool_test.utils : escapePath, TestEnv, runAndLog, makeCommand;
import dextool_test.builders;

immutable defaultBinary = "./binary";

/** Construct an execution of a compiler.
 */
auto makeCompile(const ref TestEnv testEnv, string compiler) {
    // dfmt off
    return BuildCommandRun(compiler, testEnv.outdir.escapePath)
        .commandInOutdir(false)
        .addArg("-g")
        .addInclude(testEnv.outdir.escapePath);
    // dfmt on
}

/// Use in conjunction with makeCompile to setup the default binary destination.
auto outputToDefaultBinary(BuildCommandRun br) {
    return br.addArg(["-o", (br.outdir ~ defaultBinary).escapePath]);
}

/** Add recursively all files in outdir with extension ext (including dot)
 *
 * Params:
 *  br = builder param to extend
 *  ext = extension to filter on
 *  exclude = files to exclude
 */
auto addFilesFromOutdirWithExtension(BuildCommandRun br, string ext, string[] exclude) {
    import dextool_test.utils : recursiveFilesWithExtension;

    foreach (a; recursiveFilesWithExtension(br.outdir, ext).filter!(a => !canFind(exclude,
            a.baseName.toString))) {
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

/// Add the parameter as a define (-D).
auto addDefine(BuildCommandRun br, string v) {
    return br.addArg(["-D", v]);
}

string[] compilerFlags() {
    auto default_flags = ["-std=c++98"];

    auto r = BuildCommandRun("g++").addArg("-dumpversion").yapOutput(false)
        .throwOnExitStatus(false).run;

    if (!r.success)
        return default_flags;

    if (r.stdout.length == 0 || r.stdout[0].length == 0) {
        return default_flags;
    } else if (r.stdout[0][0] == '5') {
        return default_flags ~ ["-Wpedantic", "-Werror"];
    } else {
        return default_flags ~ ["-pedantic", "-Werror"];
    }
}

deprecated("legacy function, to be removed") void testWithGTest(const Path[] src,
        const Path binary, const ref TestEnv testEnv, const string[] flags, const string[] incls) {
    immutable bool[string] rm_flag = ["-Wpedantic" : true, "-Werror" : true, "-pedantic" : true];

    auto flags_ = flags.filter!(a => a !in rm_flag).array();

    Args args;
    args ~= "g++";
    args ~= flags_.dup;
    args ~= "-g";
    args ~= "-o" ~ binary.escapePath;
    args ~= "-I" ~ testEnv.outdir.escapePath;
    args ~= "-I" ~ "fused_gmock";
    args ~= incls.dup;
    args ~= src.dup;
    args ~= "-l" ~ "gmock_gtest";
    args ~= "-lpthread";
    args ~= "-L.";

    runAndLog(args.data);
}

deprecated("legacy function, to be removed") void compileResult(const Path input, const Path binary,
        const Path main, const ref TestEnv testEnv, const string[] flags, const string[] incls) {
    Args args;
    args ~= "g++";
    args ~= flags.dup;
    args ~= "-g";
    args ~= "-o" ~ binary.escapePath;
    args ~= "-I" ~ testEnv.outdir.escapePath;
    args ~= incls.dup;
    args ~= main;

    if (exists(input)) {
        args ~= input;
    }

    runAndLog(args.data);
}
