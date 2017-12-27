/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-plugin_mutate_mutation_aor
*/
module dextool_test.mutate_aor;

import dextool_test.utility;

// dfmt off

@("shall produce all AOR mutations")
@Values("aor_primitive.cpp", "aor_object_overload.cpp")
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
        .addArg(["--mutant", "aor"])
        .run;
    verifyAor(r.stdout);
}

void verifyAor(const(string)[] txt) {
    import std.algorithm : filter;
    import std.format : format;

    const ops = ["+", "-", "*", "/", "%"];

    foreach (op; ops) {
        foreach (mut; ops.filter!(a => a != op)) {
            auto expected = format("from '%s' to '%s'", op, mut);
            dextoolYap("Testing: " ~ expected);
            txt.sliceContains(expected).shouldBeTrue;
        }
    }
}
