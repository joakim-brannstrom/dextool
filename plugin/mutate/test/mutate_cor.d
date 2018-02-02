/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-plugin_mutate_mutation_cor
*/
module dextool_test.mutate_cor;

import dextool_test.utility;

// dfmt off

@("shall produce all COR mutations for primitive types")
@Values("lcr_primitive.cpp", "lcr_overload.cpp", "lcr_in_ifstmt.cpp")
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
        .addArg(["--mutant", "cor"])
        .run;
    verifyCor(r.stdout);
}

void verifyCor(const(string)[] txt) {
    // &&
    testAnyOrder!SubStr([
        "'a && b' to 'false'",
        "'&& b' to '/*&& b*/'",
        "'a &&' to '/*a &&*/'",
        "'&&' to '=='",
    ]).shouldBeIn(txt);

    // ||
    testAnyOrder!SubStr([
        "'||' to '!='",
        "'a ||' to '/*a ||*/'",
        "'|| b' to '/*|| b*/'",
        "'a || b' to 'true'",
    ]).shouldBeIn(txt);
}
