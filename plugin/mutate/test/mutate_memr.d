/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_memr;

import std.algorithm : joiner, count;

import dextool_test.fixtures;
import dextool_test.utility;

// dfmt off

@(testId ~ "shall replace malloc with null")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "memr.c")
        .run;

    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "memr"])
        .run;

    testAnyOrder!SubStr([
        "from 'malloc(42)' to 'NULL'",
        "from 'kmalloc(42)' to 'NULL'",
        "from 'xmalloc(42)' to 'NULL'",
    ]).shouldBeIn(r.output);
}

class ShallProduceValidSchemataForMemr : SchemataFixutre {
    override string programFile() {
        return (testData ~ "memr.c").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "memr"]).run;
        testAnyOrder!SubStr([
                            "from 'malloc(42)' to 'NULL'",
                            "from 'kmalloc(42)' to 'NULL'",
                            "from 'xmalloc(42)' to 'NULL'",
        ]).shouldBeIn(r.output);
    }
}
