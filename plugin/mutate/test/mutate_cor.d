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
@Values("lcr_primitive.cpp", "lcr_overload.cpp")
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
    txt.sliceContains("'a && b' to 'false'").shouldBeTrue;
    txt.sliceContains("'&& b' to ''").shouldBeTrue;
    txt.sliceContains("'a &&' to ''").shouldBeTrue;
    txt.sliceContains("'&&' to '=='").shouldBeTrue;

    // ||
    txt.sliceContains("'||' to '!='").shouldBeTrue;
    txt.sliceContains("'a ||' to ''").shouldBeTrue;
    txt.sliceContains("'|| b' to ''").shouldBeTrue;
    txt.sliceContains("'a || b' to 'true'").shouldBeTrue;
}
