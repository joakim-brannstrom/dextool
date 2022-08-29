/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_coverage;

import core.thread : Thread;
import core.time : dur, Duration;
import std.algorithm : filter;
import std.file : readText;
import std.stdio : File;
import std.traits : EnumMembers;
import std.typecons : Yes;

import dextool_test.utility;
import dextool_test.fixtures;

class ShallUseCoverage : CoverageFixutre {
    override void test() {
        import std.json;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        // dfmt off
        makeDextoolAnalyze(testEnv)
            .addInputArg(programCode)
            .addPostArg(["--mutant", "all"])
            .addPostArg(["-c", (testData ~ "config/coverage.toml").toString])
            .run;

        runDextoolTest(testEnv).run;

        auto r =  makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--style", "json"])
            .addPostArg(["--section", "summary", "--section", "all_mut"])
            .addPostArg(["--logdir", testEnv.outdir.toString])
            .run;
        // dfmt on

        // because different libclang versions result in different number of mutants...
        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString))["stat"];
        j["alive"].integer.shouldBeGreaterThan(2);
        j["killed"].integer.shouldBeGreaterThan(1);
        j["no_coverage"].integer.shouldBeGreaterThan(1);
    }
}
