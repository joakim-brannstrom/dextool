/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_uoi;

import dextool_test.utility;

// dfmt off

@("shall successfully run the UOI mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "uoi.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "uoi"])
        .run;

    // shall NOT insert unary operators on the lhs of the assignment
    r.stdout.sliceContains("'case_2_a' to 'case_2_a").shouldBeFalse;
}
