/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_aor;

import dextool_test.utility;

// dfmt off

@("shall successfully run the AOR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "aor.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutation", "aor"])
        .run;
}
