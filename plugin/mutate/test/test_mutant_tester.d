/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_mutant_tester;

import dextool_test.utility;

// dfmt off

@("shall report the test case that killed the mutant")
unittest {
    mixin(EnvSetup(globalTestdir));

    immutable program_cpp = (testEnv.outdir ~ "program.cpp").toString;
    immutable program_bin = (testEnv.outdir ~ "program").toString;

    copy(testData ~ "test_mutant_tester_one_mutation_point.cpp", program_cpp);

    makeDextoolAnalyze(testEnv)
        .addInputArg(program_cpp)
        .run;

    immutable compile_script = (testEnv.outdir ~ "compile.sh").toString;
    immutable test_script = (testEnv.outdir ~ "test.sh").toString;
    immutable analyze_script = (testEnv.outdir ~ "analyze.sh").toString;

    File(compile_script, "w").write(format(
"#!/bin/bash
set -e
g++ %s -o %s
", program_cpp, program_bin));

    File(test_script, "w").write(
"#!/bin/bash
exit 1
");

    File(analyze_script, "w").write(format(
"#!/bin/bash
set -e
test -e $1 && echo 'Failed 42'
"
));

    makeExecutable(compile_script);
    makeExecutable(test_script);
    makeExecutable(analyze_script);

    auto r = dextool_test.makeDextool(testEnv)
        .setWorkdir(".")
        .args(["mutate"])
        .addArg(["test"])
        .addPostArg(["--mutant", "dcr"])
        .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
        .addPostArg(["--compile", compile_script])
        .addPostArg(["--test", test_script])
        .addPostArg(["--test-case-analyze-cmd", analyze_script])
        .addPostArg(["--test-timeout", "10000"])
        .run;

    testConsecutiveSparseOrder!SubStr([`Killed by ["Failed 42"]`]).shouldBeIn(r.stdout);
}
