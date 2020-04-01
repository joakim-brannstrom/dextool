/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_schemata;

import std.format : format;
import std.path : relativePath;

import dextool.plugin.mutate.backend.database.standalone : Database;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;
static import dextool.type;

import dextool_test.utility;
import dextool_test.fixtures;

class ShallRunADummySchemata : SimpleFixture {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);
        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "aor"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-cmd", analyze_script])
            .addPostArg(["--test-timeout", "10000"])
            .addPostArg(["--log-schemata"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!SubStr([
                `Running schemata`, `failed to compile`,
                ]).shouldBeIn(r.output);
    }
}
