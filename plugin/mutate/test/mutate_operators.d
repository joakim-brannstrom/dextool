/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_operators;

import dextool_test.utility;

// dfmt off

@("shall successfully run the ROR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "generate_mutant"])
        .addArg(["--mutation", "ror"])
        .addArg(["--mutation-id", "604"])
        .run;
    r.stdout.sliceContains("from '||' to '!='").shouldBeTrue;
    // wrong output
    //info: 604 Mutate from 'a || b' to '>=' in
}

@("shall successfully run the LCR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    makeDextool(testEnv)
        .addArg(["--mode", "generate_mutant"])
        .addArg(["--mutation", "lcr"])
        .run;
}

@("shall successfully run the AOR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    makeDextool(testEnv)
        .addArg(["--mode", "generate_mutant"])
        .addArg(["--mutation", "aor"])
        .run;
}

@("shall successfully run the  mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    makeDextool(testEnv)
        .addArg(["--mode", "generate_mutant"])
        .addArg(["--mutation", "uoi"])
        .run;
}
