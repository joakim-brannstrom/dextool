/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-mutation_lcr
*/
module dextool_test.mutate_lcr;

import dextool_test.utility;

@(testId ~ "shall produce all LCR mutations for primitive types")
@Values("lcr_primitive.cpp", "lcr_overload.cpp", "lcr_in_ifstmt.cpp")
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    // dfmt off
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ getValue!string)
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "lcr"])
        .run;

    testAnyOrder!SubStr([
        "from '&&' to '||'",
        "from 'a && b' to 'true'",
        "from 'a && b' to 'false'",
        "from '||' to '&&'",
        "from 'a || b' to 'true'",
        "from 'a || b' to 'false'",
    ]).shouldBeIn(r.output);
    // dfmt on
}

@(testId ~ "shall produce all LCR delete mutations for primitive types")
@Values("lcr_primitive.cpp", "lcr_overload.cpp", "lcr_in_ifstmt.cpp")
@ShouldFail unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    // dfmt off
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ getValue!string)
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "lcr"])
        .run;

    testAnyOrder!SubStr([
        "from '&& b' to ''",
        "from 'a &&' to ''",
        "from '|| b' to ''",
        "from 'a ||' to ''",
    ]).shouldBeIn(r.output);
    // dfmt on
}

@(testId ~ "shall NOT produce mutants inside template parameters")
unittest {
    mixin(envSetup(globalTestdir));

    // dfmt off
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "lcr_inside_template_param_bug.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "lcr"])
        .run;
    // dfmt on

    testAnyOrder!SubStr(["from '&&' to '||'",]).shouldNotBeIn(r.output);

    testAnyOrder!SubStr(["from '||' to '&&'",]).shouldNotBeIn(r.output);
}
