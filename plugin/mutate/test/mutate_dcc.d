/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-plugin_mutate_mutation_dcc
*/
module dextool_test.mutate_dcc;

import dextool_test.utility;

// dfmt off

@("shall produce 2 predicate mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dcc_dc_ifstmt1.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "dcc"])
        .run;
    r.stdout.sliceContains("from 'x' to 'true'").shouldBeTrue;
    r.stdout.sliceContains("from 'x' to 'false'").shouldBeTrue;
}

@("shall produce 4 predicate mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dcc_dc_ifstmt2.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "dcc"])
        .run;
    r.stdout.sliceContains("from 'x' to 'true'").shouldBeTrue;
    r.stdout.sliceContains("from 'x' to 'false'").shouldBeTrue;
    r.stdout.sliceContains("from 'y' to 'true'").shouldBeTrue;
    r.stdout.sliceContains("from 'y' to 'false'").shouldBeTrue;
}

@("shall produce 2 predicate mutations for an expression of multiple clauses")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dcc_dc_ifstmt3.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "dcc"])
        .run;
    r.stdout.sliceContains("from 'x == 0 || y == 0' to 'true'").shouldBeTrue;
    r.stdout.sliceContains("from 'x == 0 || y == 0' to 'false'").shouldBeTrue;
}

@("shall produce 6 clause mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dcc_cc_ifstmt1.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "dcc"])
        .run;
    r.stdout.sliceContains("from 'x == 0' to 'true'").shouldBeTrue;
    r.stdout.sliceContains("from 'x == 0' to 'false'").shouldBeTrue;
    r.stdout.sliceContains("from 'x == 1' to 'true'").shouldBeTrue;
    r.stdout.sliceContains("from 'x == 1' to 'false'").shouldBeTrue;
    r.stdout.sliceContains("from 'x == 2' to 'true'").shouldBeTrue;
    r.stdout.sliceContains("from 'x == 2' to 'false'").shouldBeTrue;

    r.stdout.joiner.count("'x == 0'").shouldEqual(2);
    r.stdout.joiner.count("'x == 1'").shouldEqual(2);
    r.stdout.joiner.count("'x == 2'").shouldEqual(2);
}
