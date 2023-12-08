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
    makeDextoolAnalyze(testEnv).addArg(["--threads", "1"]).addInputArg(testData ~ "cr.cpp").run;
    auto r = makeDextool(testEnv).addArg(["test"]).run;
    testAnyOrder!SubStr([
        "from '42' to '0'", "from '2.0' to '0.0'", "from '3.0' to '0.0'",
        "from '28.0' to '0.0'", "from '23.0' to '0.0'", "from '55' to '0'",
        "from '88' to '0'"
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce all CR mutations without duplications")
unittest {
    import std.json;
    import std.file : readText;
    import std.string : endsWith;
    import std.algorithm : filter, count;
    import clang.c.Index : CINDEX_VERSION_MAJOR, CINDEX_VERSION_MINOR;

    // tests only passes with clang-15
    static if (!(CINDEX_VERSION_MAJOR > 0 || CINDEX_VERSION_MINOR >= 62))
        return;

    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "cr_complex.cpp")
        .addInputArg(testData ~ "cr_complex2.cpp").run;

    auto r = makeDextoolReport(testEnv, testData.dirName).addArg([
        "--style", "json"
    ]).addArg(["--section", "all_mut"]).addArg([
        "--logdir", testEnv.outdir.toString
    ]).run;

    auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString));
    j["files"].array.length.shouldEqual(3);
    foreach (jj; j["files"].array) {
        if (jj["filename"].str.endsWith("cr_complex.hpp")) {
            jj["mutants"].array.filter!(a => a["kind"].str == "crZeroInt").count.shouldEqual(6);
        } else if (jj["filename"].str.endsWith("cr_complex.cpp")) {
            jj["mutants"].array.filter!(a => a["kind"].str == "crZeroInt").count.shouldEqual(2);
        } else {
            jj["mutants"].array.length.shouldEqual(1);
        }
    }
}
