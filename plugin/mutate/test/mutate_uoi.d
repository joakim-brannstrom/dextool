/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_uoi;

import dextool_test.utility;

// dfmt off

@("shall successfully run the UOI mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "unary_op_insert.cpp")
        .addArg(["--mode", "analyzer"])
        .addArg(["--mutation", "uoi"])
        .run;
    makeDextool(testEnv)
        .addArg(["--mode", "generate_mutant"])
        .run;
}
