/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_lcrb;

import dextool_test.utility;

// dfmt off

@("shall produce all lcrb mutations for primitive types")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "lcrb_primitive.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "lcrb"])
        .run;

    testAnyOrder!SubStr([
        "from '&' to '|'",
        "from '|' to '&'"
    ]).shouldBeIn(r.stdout);
}
