/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool_test.integration;

import scriptlike;
import unit_threaded : shouldEqual;

import dextool_test.utils;

enum globalTestdir = "compiledb_tests";

struct TestParams {
    Path root;
    Path[] input;
    Path out_db;

    // dextool parameters;
    string[] dexParams;
    string[] dexFlags;

    // Compiler flags
    string[] compileFlags;
    string[] compileIncls;
}

TestParams genTestParams(string[] f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("plugin_testdata").absolutePath;
    p.input = f.map!(a => p.root ~ Path(a)).array();

    p.out_db = testEnv.outdir ~ "compile_commands.json";

    p.dexParams = ["--DRT-gcopt=profile:1", "compiledb", "--debug"];
    p.dexFlags = [];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv,
        Flag!"sortLines" sortLines = No.sortLines,
        Flag!"skipComments" skipComments = Yes.skipComments) {

    dextoolYap("Input:%s", p.input);
    string[] input = p.input.map!(a => a.raw).array();
    runDextool2(testEnv, p.dexParams ~ input, null);
}

@(testId ~ "shall merge the db to one with absolute paths")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams(["db1.json", "db2.json"], testEnv);
    runTestFile(p, testEnv);
    // incidental check by counting the lines. not perfect but good enough for
    // now
    std.file.readText(p.out_db.toString).splitter("\n").count.shouldEqual(28);
}
