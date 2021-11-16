/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_cr;

import dextool_test.utility;

@(testId ~ "shall produce all CR mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "cr.cpp").run;
    auto r = makeDextool(testEnv).addArg(["test"]).addArg(["--mutant", "cr"]).run;
    testAnyOrder!SubStr(["from '42' to '0'"]).shouldBeIn(r.output);
}
