/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.xml_files;

import dextool_test.utility;

// dfmt off

@("shall be dextool <plugin> as the first two arguments in the logfile")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/test_logging.h")
        .run;
    readXmlLog(testEnv).sliceContains("dextool_debug ctestdouble").shouldBeTrue;
}
