/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.generate_mutant;

import std.file : copy, readText;

import dextool_test.utility;

// dfmt off

@(testId ~ "shall inject a mutant")
unittest {
    mixin(EnvSetup(globalTestdir));

    immutable dst = testEnv.outdir ~ "report_one_ror_mutation_point.cpp";
    const originalFname = (testData ~ "report_one_ror_mutation_point.cpp").toString;

    copy(originalFname, dst.toString);

    makeDextoolAnalyze(testEnv)
        .addInputArg(dst)
        .run;
    auto r = dextool_test.makeDextool(testEnv)
        .setWorkdir(workDir)
        .args(["mutate"])
        .addArg(["generate"])
        .addArg(["--id", "1"])
        .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
        .run;

    auto original = readText(originalFname);
    auto mutated = readText(dst.toString);

    original.shouldNotEqual(mutated);
}
