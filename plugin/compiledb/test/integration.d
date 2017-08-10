/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.integration;

import scriptlike;
import unit_threaded : shouldEqual, shouldBeTrue;

import dextool_test.utils;

enum globalTestdir = "compiledb_tests";

immutable compiledbJsonFile = "compile_commands.json";

auto makeDextool(const ref TestEnv testEnv) {
    return dextool_test.utils.makeDextool(testEnv).args(["compiledb", "-d"]);
}

auto testData() {
    return Path("plugin_testdata").absolutePath;
}

auto readJson(const ref TestEnv testEnv) {
    return std.file.readText((testEnv.outdir ~ compiledbJsonFile).toString).splitLines.array();
}

@(testId ~ "shall merge the db to one with absolute paths")
unittest {
    mixin(envSetup(globalTestdir));

    makeDextool(testEnv).addArg(testData ~ "db1.json").addArg(testData ~ "db2.json").run;

    // incidental check by counting the lines. not perfect but good enough for
    // now
    readJson(testEnv).count.shouldEqual(27);
}

@(
        testId
        ~ "shall produce a merged DB with the fields arguments and command preserved with absolute paths")
unittest {
    mixin(envSetup(globalTestdir));

    makeDextool(testEnv).addArg(testData ~ "db1.json").addArg(testData ~ "compile_db_v5.json").run;

    // incidental check by counting the lines. not perfect but good enough for
    // now
    readJson(testEnv).count.shouldEqual(26);
}
