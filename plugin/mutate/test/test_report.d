/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_report;

import dextool_test.utility;

@("shall generate a report of the content in the database")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "lcr.cpp").addArg(["--mode", "analyzer"]).run;
    makeDextool(testEnv).addArg(["--mode", "report"]).run;
}
