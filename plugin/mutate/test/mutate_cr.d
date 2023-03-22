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
        "from '42' to '0'", "from '2.0' to '0'", "from '3.0' to '0'",
        "from '28.0' to '0'", "from '23.0' to '0'", "from '55' to '0'",
        "from '88' to '0'"
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce all CR mutations without duplications")
unittest {
    import std.json;
    import std.file : readText;
    import std.stdio : writeln;

    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "cr_complex.cpp")
        .addInputArg(testData ~ "cr_complex2.cpp").run;

    auto r = makeDextoolReport(testEnv, testData.dirName).addArg([
        "--style", "json"
    ]).addArg(["--section", "all_mut"]).addArg([
        "--logdir", testEnv.outdir.toString
    ]).run;

    try {
        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString));
        j["files"].array.length.shouldEqual(2);
        foreach (jj; j["files"].array) {
            jj["mutants"].array.length.shouldEqual(1);
            jj["mutants"].array[0]["kind"].str.shouldEqual("crZero");
        }
    } catch (Exception e) {
        writeln(e.msg);
    }
}
