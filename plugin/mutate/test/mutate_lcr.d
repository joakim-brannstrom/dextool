/**
Copyright: Copyright (c) Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-mutation_lcr
*/
module dextool_test.mutate_lcr;

import dextool_test.utility;

@(testId ~ "shall produce all LCR mutations for primitive types")
unittest {
    mixin(envSetup(globalTestdir));

        makeDextoolAnalyze(testEnv).addInputArg(testData ~ "lcr_primitive.cpp").addArg([
            "--mutant", "lcr"
        ]).run;
        auto r = makeDextool(testEnv).addArg(["test"]).run;
        checkContent(r.output);
    testAnyOrder!Re([
        `from '\\|\\|' to '&&'.*:20`,
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce all LCR mutations for primitive types")
unittest {
    mixin(envSetup(globalTestdir));

        makeDextoolAnalyze(testEnv).addInputArg(testData ~ "lcr_in_ifstmt.cpp").addArg([
            "--mutant", "lcr"
        ]).run;
        auto r = makeDextool(testEnv).addArg(["test"]).run;
        checkContent(r.output);
    testAnyOrder!Re([
        `from '\\|\\|' to '&&'.*:22`,
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce all LCR mutations for primitive types")
unittest {
    mixin(envSetup(globalTestdir));

        makeDextoolAnalyze(testEnv).addInputArg(testData ~ "lcr_overload.cpp").addArg([
            "--mutant", "lcr"
        ]).run;
        auto r = makeDextool(testEnv).addArg(["test"]).run;
        checkContent(r.output);
    testAnyOrder!Re([
        `from '\\|\\|' to '&&'.*:29`,
    ]).shouldBeIn(r.output);
}

void checkContent(string[] output) {
    // dfmt off
    testAnyOrder!SubStr([
        "from '&& ' to '||'",
        "from 'and ' to '||'",
        "from 'a && b' to 'true'",
        "from 'a && b' to 'false'",
        "from '|| ' to '&&'",
        "from 'or ' to '&&'",
        "from 'a || b' to 'true'",
        "from 'a || b' to 'false'",
        "from 'a and b' to 'false'",
        "from 'a and b' to 'false'",
        "from 'a or b' to 'false'",
        "from 'a or b' to 'false'",
    ]).shouldBeIn(output);
    // dfmt on
}

@(testId ~ "shall NOT produce mutants inside template parameters")
unittest {
    mixin(envSetup(globalTestdir));

    // dfmt off
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "lcr_inside_template_param_bug.cpp")
        .addArg(["--mutant", "lcr"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .run;
    // dfmt on

    testAnyOrder!SubStr(["from '&& ' to '||'",]).shouldNotBeIn(r.output);
    testAnyOrder!SubStr(["from '|| ' to '&&'",]).shouldNotBeIn(r.output);
}

@(testId ~ "shall produce all lcrb mutations for primitive types when using --mutant lcr")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "lcrb_primitive.cpp")
        .addArg(["--mutant", "lcr"]).run;
    auto r = makeDextool(testEnv).addArg(["test"]).run;

    // dfmt off
    testAnyOrder!SubStr([
        "from '& ' to '|'",
        "from 'a & ' to ''",
        "from '& b' to ''",
        "from '| ' to '&'",
        "from 'a | ' to ''",
        "from '| b' to ''",
    ]).shouldBeIn(r.output);
    // dfmt on
}
