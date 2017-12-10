/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_ror;

import dextool_test.utility;

// dfmt off

@("shall successfully run the ROR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "ror.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "ror"])
        .run;
    r.stdout.sliceContains("'<' to '<='").shouldBeTrue;
    // wrong output
    //info: 604 Mutate from 'a || b' to '>=' in
}
