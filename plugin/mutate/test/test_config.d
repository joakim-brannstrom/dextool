/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module test the configuration functionality.
*/
module dextool_test.test_config;

import dextool_test.utility;

@(testId ~ "shall read the config sections without errors")
unittest {
    mixin(EnvSetup(globalTestdir));

    immutable conf = (testEnv.outdir ~ ".dextool_mutate.toml").toString;

    copy(testData ~ "config/all_section.toml", conf);
    File((testEnv.outdir ~ "compile_commands.json").toString, "w").write("[]");

    auto res = makeDextoolAnalyze(testEnv).addArg(["-c", (testEnv.outdir ~ ".dextool_mutate.toml").toString])
        .addArg(["--compile-db", (testEnv.outdir ~ "compile_commands.json").toString]).run;

    res.success.shouldBeTrue;
}

@(testId ~ "shall create a config file when called with --init from admin subcommand")
unittest {
    mixin(EnvSetup(globalTestdir));

    auto res = makeDextool(testEnv).setWorkdir(null).args(["mutate", "admin"])
        .postArg(["-c", (testEnv.outdir ~ "myconf.toml").toString]).addPostArg("--init").run;

    exists((testEnv.outdir ~ "myconf.toml").toString).shouldBeTrue;
}

@(testId ~ "shall read the test groups when reporting")
unittest {
    mixin(EnvSetup(globalTestdir));

    immutable conf = (testEnv.outdir ~ ".dextool_mutate.toml").toString;

    copy(testData ~ "config/read_test_groups.toml", conf);
    File((testEnv.outdir ~ "compile_commands.json").toString, "w").write("[]");

    auto r = makeDextoolAnalyze(testEnv).addArg(["-c", (testEnv.outdir ~ ".dextool_mutate.toml").toString])
        .addArg(["--compile-db", (testEnv.outdir ~ "compile_commands.json").toString]).run;

    testConsecutiveSparseOrder!SubStr(["uc1, Parameterized Tests, Value.*|TypeTrait.*|Typed.*"]).shouldBeIn(
            r.stdout);
    testConsecutiveSparseOrder!SubStr(
            ["uc2, Test Report, TestResult.*|TestPartResult.*|TestInfo.*"]).shouldBeIn(r.stdout);
    testConsecutiveSparseOrder!SubStr(["uc3, Resetting Mocks, VerifyAndClear.*"]).shouldBeIn(
            r.stdout);
}
