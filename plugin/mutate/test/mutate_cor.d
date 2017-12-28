/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_cor;

import dextool_test.utility;

// dfmt off

@("shall successfully run the COD mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "lcr_primitive.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "cor"])
        .run;

    // &&
    r.stdout.sliceContains("'a && b' to 'false'").shouldBeTrue;
    r.stdout.sliceContains("'&& b' to ''").shouldBeTrue;
    r.stdout.sliceContains("'a &&' to ''").shouldBeTrue;
    r.stdout.sliceContains("'&&' to '=='").shouldBeTrue;

    // ||
    r.stdout.sliceContains("'||' to '!='").shouldBeTrue;
    r.stdout.sliceContains("'a ||' to ''").shouldBeTrue;
    r.stdout.sliceContains("'|| b' to ''").shouldBeTrue;
    r.stdout.sliceContains("'a || b' to 'true'").shouldBeTrue;
}
