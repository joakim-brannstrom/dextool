/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-plugin_mutate_mutation_lcr
*/
module dextool_test.mutate_lcr;

import dextool_test.utility;

// dfmt off

@("shall produce all LCR mutations for primitive types")
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
        .addArg(["--mutant", "lcr"])
        .run;
    verifyLcr(r.stdout);
}

void verifyLcr(const(string)[] txt) {
    txt.sliceContains("from '&&' to '||'").shouldBeTrue;
    txt.sliceContains("from '||' to '&&'").shouldBeTrue;
}
