/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_d2sqlite3_cleanup_bug;

import dextool_test.utility;

// dfmt off

@("shall close the sqlite3 database without reliance on the GC")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto r = makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "junkfile.cpp")
        .run;

    testConsecutiveSparseOrder!SubStr([
        `clean-up of Database incorrectly depends on destructors called by the GC`
    ]).shouldNotBeIn(r.stderr);
}
