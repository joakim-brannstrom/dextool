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

    testConsecutiveSparseOrder!SubStr([`killed by ["Failed 42"]`]).shouldBeIn(r.stdout);
}

@("shall parse a gtest report for the test cases that killed the mutant")
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
cat <<EOF
Running main() from gtest_main.cc
[==========] Running 17 tests from 1 test case.
[----------] Global test environment set-up.
[----------] 17 tests from MessageTest
[ RUN      ] MessageTest.DefaultConstructor
/home/smurf/googletest/test/gtest-message_test.cc:48: Failure
Expected equality of these values:
  true
  false
[  FAILED  ] MessageTest.DefaultConstructor (0 ms)
[ RUN      ] MessageTest.CopyConstructor
[       OK ] MessageTest.CopyConstructor (0 ms)
[ RUN      ] MessageTest.ConstructsFromCString
[       OK ] MessageTest.ConstructsFromCString (0 ms)
[ RUN      ] MessageTest.StreamsFloat
[       OK ] MessageTest.StreamsFloat (0 ms)
[ RUN      ] MessageTest.StreamsDouble
[       OK ] MessageTest.StreamsDouble (0 ms)
[ RUN      ] MessageTest.StreamsPointer
[       OK ] MessageTest.StreamsPointer (0 ms)
[ RUN      ] MessageTest.StreamsNullPointer
[       OK ] MessageTest.StreamsNullPointer (0 ms)
/home/smurf/googletest/test/gtest-message_test.cc:42: Failure
Expected equality of these values:
  true
  false
[  FAILED  ] MessageTest.StreamsNullPointer (0 ms)
[ RUN      ] MessageTest.StreamsCString
[       OK ] MessageTest.StreamsCString (0 ms)
[ RUN      ] MessageTest.StreamsNullCString
[       OK ] MessageTest.StreamsNullCString (0 ms)
[ RUN      ] MessageTest.StreamsString
[       OK ] MessageTest.StreamsString (0 ms)
[ RUN      ] MessageTest.StreamsStringWithEmbeddedNUL
[       OK ] MessageTest.StreamsStringWithEmbeddedNUL (0 ms)
[ RUN      ] MessageTest.StreamsNULChar
[       OK ] MessageTest.StreamsNULChar (0 ms)
[ RUN      ] MessageTest.StreamsInt
[       OK ] MessageTest.StreamsInt (0 ms)
[ RUN      ] MessageTest.StreamsBasicIoManip
[       OK ] MessageTest.StreamsBasicIoManip (0 ms)
[ RUN      ] MessageTest.GetString
[       OK ] MessageTest.GetString (0 ms)
[ RUN      ] MessageTest.StreamsToOStream
[       OK ] MessageTest.StreamsToOStream (0 ms)
[ RUN      ] MessageTest.DoesNotTakeUpMuchStackSpace
[       OK ] MessageTest.DoesNotTakeUpMuchStackSpace (0 ms)
[----------] 17 tests from MessageTest (0 ms total)

[----------] Global test environment tear-down
[==========] 17 tests from 1 test case ran. (0 ms total)
[  PASSED  ] 15 tests.
[  FAILED  ] 2 test, listed below:
[  FAILED  ] MessageTest.DefaultConstructor

 2 FAILED TEST
EOF
exit 1
");

    makeExecutable(compile_script);
    makeExecutable(test_script);

    auto r = dextool_test.makeDextool(testEnv)
        .setWorkdir(".")
        .args(["mutate"])
        .addArg(["test"])
        .addPostArg(["--mutant", "dcr"])
        .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
        .addPostArg(["--compile", compile_script])
        .addPostArg(["--test", test_script])
        .addPostArg(["--test-case-analyze-builtin", "gtest"])
        .addPostArg(["--test-timeout", "10000"])
        .run;

    testConsecutiveSparseOrder!SubStr([`killed by ["../../../../../../../smurf/googletest/test/gtest-message_test.cc:MessageTest.DefaultConstructor","../../../../../../../smurf/googletest/test/gtest-message_test.cc:MessageTest.StreamsNullPointer"]`]).shouldBeIn(r.stdout);
}
