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
}
