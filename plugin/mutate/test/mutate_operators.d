/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_operators;

import dextool_test.utility;

// dfmt off

@("shall successfully run the ROR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mutation", "ror"])
        .run;
}

@("shall successfully run the LCR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mutation", "lcr"])
        .run;
}

@("shall successfully run the AOR mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mutation", "aor"])
        .run;
}

@("shall successfully run the  mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "all_binary_ops.cpp")
        .addArg(["--mutation", "uor"])
        .run;
}
