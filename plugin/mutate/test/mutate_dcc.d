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
@Values("dcc_dc_ifstmt3.cpp", "dcc_dc_stmt3.cpp")
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    makeDextool(testEnv)
        .addInputArg(testData ~ getValue!string)
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "dcc"])
        .run;
    makeSubSeq!SubStr([
        "from 'x == 0 || y == 0' to 'true'",
        "from 'x == 0 || y == 0' to 'false'",
    ]).shouldBeIn(r.stdout);
}

@("shall produce 6 clause mutations")
@Values("dcc_cc_ifstmt1.cpp", "dcc_cc_stmt1.cpp")
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    makeDextool(testEnv)
        .addInputArg(testData ~ getValue!string)
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "dcc"])
        .run;
    makeSubSeq!SubStr([
        "from 'x == 0' to 'true'",
        "from 'x == 0' to 'false'",
        "from 'x == 1' to 'true'",
        "from 'x == 1' to 'false'",
        "from 'x == 2' to 'true'",
        "from 'x == 2' to 'false'",
        "from 'y > 0' to 'true'",
        "from 'y > 0' to 'false'",
        "from 'x > 2' to 'true'",
        "from 'x > 2' to 'false'",
    ]).shouldBeIn(r.stdout);

    r.stdout.joiner.count("'x == 0'").shouldEqual(2);
    r.stdout.joiner.count("'x == 1'").shouldEqual(2);
    r.stdout.joiner.count("'x == 2'").shouldEqual(2);
    r.stdout.joiner.count("'y > 0'").shouldEqual(2);
    r.stdout.joiner.count("'x > 2'").shouldEqual(2);
}

@("shall produce 4 switch bomb mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dcc_dc_switch1.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "dcc"])
        .run;
    makeSubSeq!SubStr([
        "from 'return -1 ;' to '*((char*)0)='x';break;'",
        "from 'return 1;' to '*((char*)0)='x';break;'",
        "from 'break;' to '*((char*)0)='x';break;'",
        "from '' to '*((char*)0)='x';break;'",
    ]).shouldBeIn(r.stdout);
}
