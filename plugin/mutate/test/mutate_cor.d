/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-mutation_cor
*/
module dextool_test.mutate_cor;

import dextool_test.utility;

// dfmt off

// COR mutants are not supported anymore because they where found to produce
// unproductive effective mutants. Hard to understand.
@(ShouldFail)
@("shall produce all COR mutations for primitive types")
@Values("lcr_primitive.cpp", "lcr_overload.cpp", "lcr_in_ifstmt.cpp")
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ getValue!string)
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "cor"])
        .run;
    verifyCor(r.output);
}

void verifyCor(const(string)[] txt) {
    // &&
    testAnyOrder!SubStr([
        "'a && b' to 'false'",
        "'&& b' to ''",
        "'a &&' to ''",
        "'&&' to '=='",
    ]).shouldBeIn(txt);

    // ||
    testAnyOrder!SubStr([
        "'||' to '!='",
        "'a ||' to ''",
        "'|| b' to ''",
        "'a || b' to 'true'",
    ]).shouldBeIn(txt);
}
