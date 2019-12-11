/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_mutant_tester;

import core.thread : Thread;
import core.time : dur;
import std.algorithm : filter;
import std.file : readText;
import std.stdio : File;
import std.traits : EnumMembers;
import std.typecons : Yes;

import dextool_test.utility;
import dextool_test.fixtures;

class ShallReportTestCaseKilledMutant : SimpleFixture {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-cmd", analyze_script])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!SubStr([`killed by [Failed 42]`]).shouldBeIn(r.stdout);
    }
}

class ShallParseGtestReportForTestCasesThatKilledTheMutant : SimpleFixture {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-builtin", "gtest"])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!SubStr(
                [
                `killed by [MessageTest.DefaultConstructor, MessageTest.StreamsNullPointer]`
                ]).shouldBeIn(r.stdout);
    }

    override string scriptTest() {
        return "#!/bin/bash
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
";
    }
}

class ShallParseCTestReportForTestCasesThatKilledTheMutant : SimpleFixture {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-builtin", "ctest"])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!SubStr([
                `killed by [gtest-typed-test_test, gtest_list_tests_unittest, gtest_no_rtti_unittest, gtest_output_test, gtest_unittest, gtest_xml_output_unittest]`
                ]).shouldBeIn(r.stdout);
    }

    override string scriptTest() {
        return `#!/bin/bash
cat <<EOF
Test project /dev/shm/gtest_mut
      Start 41: gtest_unittest
      Start 45: gtest_no_rtti_unittest
      Start 35: gtest_repeat_test
      Start 30: gtest-port_test
 1/60 Test #45: gtest_no_rtti_unittest ..................***Exception: Other  0.30 sec
/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_unittest.cc:3184: Test DISABLED_ShouldNotRun is listed more than once.
You forgot to list test DISABLED_ShouldNotRun.

      Start  9: gmock-matchers_test
 2/60 Test #41: gtest_unittest ..........................***Exception: Other  0.30 sec
/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_unittest.cc:3184: Test DISABLED_ShouldNotRun is listed more than once.
You forgot to list test DISABLED_ShouldNotRun.

      Start  1: gmock-actions_test
 3/60 Test  #1: gmock-actions_test ......................   Passed    0.81 sec
 4/60 Test  #9: gmock-matchers_test .....................   Passed    1.34 sec
      Start 48: gtest_break_on_failure_unittest
      Start 52: gtest_filter_unittest
 5/60 Test #48: gtest_break_on_failure_unittest .........   Passed    0.72 sec
      Start 57: gtest_throw_on_failure_test
 6/60 Test #52: gtest_filter_unittest ...................   Passed    0.72 sec
 7/60 Test #30: gtest-port_test .........................   Passed    2.39 sec
 8/60 Test #35: gtest_repeat_test .......................   Passed    2.39 sec
      Start 40: gtest-typed-test_test
      Start 20: gtest-death-test_test
      Start 38: gtest-test-part_test
 9/60 Test #40: gtest-typed-test_test ...................***Exception: Other  0.20 sec
/dev/shm/gtest_mut/gtest_src/googletest/test/gtest-typed-test_test.h:62: Test CanBeDefaultConstructed is listed more than once.
Test InitialSizeIsZero is listed more than once.
You forgot to list test CanBeDefaultConstructed.
You forgot to list test InitialSizeIsZero.

      Start  8: gmock-internal-utils_test
10/60 Test #38: gtest-test-part_test ....................   Passed    0.30 sec
11/60 Test #57: gtest_throw_on_failure_test .............   Passed    0.64 sec
      Start 37: gtest_stress_test
      Start 19: gmock_no_rtti_test
12/60 Test #20: gtest-death-test_test ...................   Passed    0.61 sec
13/60 Test  #8: gmock-internal-utils_test ...............   Passed    0.30 sec
14/60 Test #37: gtest_stress_test .......................   Passed    0.16 sec
      Start 13: gmock-spec-builders_test
      Start 17: gmock_use_own_tuple_test
      Start 47: gtest_use_own_tuple_test
15/60 Test #19: gmock_no_rtti_test ......................   Passed    0.17 sec
16/60 Test #17: gmock_use_own_tuple_test ................   Passed    0.13 sec
17/60 Test #13: gmock-spec-builders_test ................   Passed    0.13 sec
      Start 29: gtest-param-test_test
      Start 55: gtest_output_test
      Start 51: gtest_env_var_test
18/60 Test #47: gtest_use_own_tuple_test ................   Passed    0.24 sec
19/60 Test #29: gtest-param-test_test ...................   Passed    0.20 sec
      Start 16: gmock_stress_test
      Start 50: gtest_color_test
20/60 Test #51: gtest_env_var_test ......................   Passed    0.20 sec
21/60 Test #16: gmock_stress_test .......................   Passed    0.24 sec
      Start 60: gtest_xml_output_unittest
      Start 56: gtest_shuffle_test
22/60 Test #50: gtest_color_test ........................   Passed    0.36 sec
      Start 53: gtest_help_test
23/60 Test #56: gtest_shuffle_test ......................   Passed    0.30 sec
24/60 Test #53: gtest_help_test .........................   Passed    0.09 sec
25/60 Test #55: gtest_output_test .......................***Failed    0.85 sec
F
======================================================================
FAIL: testOutput (__main__.GTestOutputTest)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_output_test.py", line 320, in testOutput
    self.assertEqual(normalized_golden, normalized_actual)
AssertionError: 'The non-test part of the code is expected[26264 chars]s.\n' != 'gtest_output_test_.cc:#: Test Success is [647 chars]s.\n'
Diff is 26653 characters long. Set self.maxDiff to None to see it.

----------------------------------------------------------------------
Ran 1 test in 0.610s

FAILED (failures=1)

26/60 Test #60: gtest_xml_output_unittest ...............***Failed    0.44 sec
/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_output_unittest.py:223: DeprecationWarning: Please use assertTrue instead.
  self.assert_(p.exited)
/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_output_unittest.py:224: DeprecationWarning: Please use assertEqual instead.
  self.assertEquals(0, p.exit_code)
./dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_test_utils.py:75: DeprecationWarning: Please use assertEqual instead.
  self.assertEquals(Node.ELEMENT_NODE, actual_node.nodeType)
/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_test_utils.py:92: DeprecationWarning: Please use assertTrue instead.
  (expected_attr.name, actual_node.tagName))
.FF.
======================================================================
FAIL: testFilteredTestXmlOutput (__main__.GTestXMLOutputUnitTest)
Verifies XML output when a filter is applied.
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_output_unittest.py", line 264, in testFilteredTestXmlOutput
    extra_args=['%s=SuccessfulTest.*' % GTEST_FILTER_FLAG])
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_output_unittest.py", line 300, in _TestXmlOutput
    expected_exit_code)
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_output_unittest.py", line 280, in _GetXmlOutput
    '%s was killed by signal %d' % (gtest_prog_name, p.signal))
AssertionError: False is not true : gtest_xml_output_unittest_ was killed by signal 6

======================================================================
FAIL: testSuppressedXmlOutput (__main__.GTestXMLOutputUnitTest)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_xml_output_unittest.py", line 246, in testSuppressedXmlOutput
    '%s was killed by signal %d' % (GTEST_PROGRAM_NAME, p.signal))
AssertionError: True is not false : gtest_xml_output_unittest_ was killed by signal 6

----------------------------------------------------------------------
Ran 5 tests in 0.233s

FAILED (failures=2)

      Start 54: gtest_list_tests_unittest
      Start 49: gtest_catch_exceptions_test
      Start 59: gtest_xml_outfiles_test
      Start 58: gtest_uninitialized_test
27/60 Test #58: gtest_uninitialized_test ................   Passed    0.07 sec
28/60 Test #59: gtest_xml_outfiles_test .................   Passed    0.08 sec
29/60 Test #49: gtest_catch_exceptions_test .............   Passed    0.10 sec
      Start 12: gmock-port_test
      Start 15: gmock_test
      Start 11: gmock-nice-strict_test
30/60 Test #11: gmock-nice-strict_test ..................   Passed    0.01 sec
31/60 Test #15: gmock_test ..............................   Passed    0.01 sec
32/60 Test #12: gmock-port_test .........................   Passed    0.01 sec
      Start  5: gmock-generated-function-mockers_test
      Start 14: gmock_link_test
      Start 33: gtest-printers_test
33/60 Test #33: gtest-printers_test .....................   Passed    0.00 sec
34/60 Test #14: gmock_link_test .........................   Passed    0.01 sec
35/60 Test  #5: gmock-generated-function-mockers_test ...   Passed    0.01 sec
      Start  7: gmock-generated-matchers_test
      Start 46: gtest-tuple_test
      Start 24: gtest-listener_test
36/60 Test #24: gtest-listener_test .....................   Passed    0.00 sec
37/60 Test #46: gtest-tuple_test ........................   Passed    0.00 sec
38/60 Test  #7: gmock-generated-matchers_test ...........   Passed    0.01 sec
      Start 36: gtest_sole_header_test
      Start 42: gtest-unittest-api_test
      Start 43: gtest-death-test_ex_nocatch_test
39/60 Test #43: gtest-death-test_ex_nocatch_test ........   Passed    0.00 sec
40/60 Test #42: gtest-unittest-api_test .................   Passed    0.01 sec
41/60 Test #36: gtest_sole_header_test ..................   Passed    0.01 sec
      Start 31: gtest_pred_impl_unittest
      Start 44: gtest-death-test_ex_catch_test
      Start 22: gtest-filepath_test
42/60 Test #31: gtest_pred_impl_unittest ................   Passed    0.01 sec
43/60 Test #54: gtest_list_tests_unittest ...............***Failed    0.66 sec
/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_list_tests_unittest.py:171: DeprecationWarning: Please use assertTrue instead.
  (LIST_TESTS_FLAG, flag_expression, ' '.join(args), output)))
.FFF
======================================================================
FAIL: testFlag (__main__.GTestListTestsUnitTest)
Tests using the --gtest_list_tests flag.
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_list_tests_unittest.py", line 188, in testFlag
    other_flag=None)
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_list_tests_unittest.py", line 166, in RunAndVerify
    expected_output_re.pattern)))
AssertionError: None is not true : when gtest_list_tests is 1, the output of "--gtest_list_tests" is "",
which does not match regex "FooDeathTest\.
  Test1
Foo\.
  Bar1
  Bar2
  DISABLED_Bar3
Abc\.
  Xyz
  Def
FooBar\.
  Baz
FooTest\.
  Test1
  DISABLED_Test2
  Test3
TypedTest/0\.  # TypeParam = (VeryLo{245}|class VeryLo{239})\.\.\.
  TestA
  TestB
TypedTest/1\.  # TypeParam = int\s*\*( __ptr64)?
  TestA
  TestB
TypedTest/2\.  # TypeParam = .*MyArray<bool,\s*42>
  TestA
  TestB
My/TypeParamTest/0\.  # TypeParam = (VeryLo{245}|class VeryLo{239})\.\.\.
  TestA
  TestB
My/TypeParamTest/1\.  # TypeParam = int\s*\*( __ptr64)?
  TestA
  TestB
My/TypeParamTest/2\.  # TypeParam = .*MyArray<bool,\s*42>
  TestA
  TestB
MyInstantiation/ValueParamTest\.
  TestA/0  # GetParam\(\) = one line
  TestA/1  # GetParam\(\) = two\\nlines
  TestA/2  # GetParam\(\) = a very\\nlo{241}\.\.\.
  TestB/0  # GetParam\(\) = one line
  TestB/1  # GetParam\(\) = two\\nlines
  TestB/2  # GetParam\(\) = a very\\nlo{241}\.\.\.
"

======================================================================
FAIL: testOverrideNonFilterFlags (__main__.GTestListTestsUnitTest)
Tests that --gtest_list_tests overrides the non-filter flags.
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_list_tests_unittest.py", line 195, in testOverrideNonFilterFlags
    other_flag='--gtest_break_on_failure')
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_list_tests_unittest.py", line 166, in RunAndVerify
    expected_output_re.pattern)))
AssertionError: None is not true : when gtest_list_tests is 1, the output of "--gtest_list_tests --gtest_break_on_failure" is "",
which does not match regex "FooDeathTest\.
  Test1
Foo\.
  Bar1
  Bar2
  DISABLED_Bar3
Abc\.
  Xyz
  Def
FooBar\.
  Baz
FooTest\.
  Test1
  DISABLED_Test2
  Test3
TypedTest/0\.  # TypeParam = (VeryLo{245}|class VeryLo{239})\.\.\.
  TestA
  TestB
TypedTest/1\.  # TypeParam = int\s*\*( __ptr64)?
  TestA
  TestB
TypedTest/2\.  # TypeParam = .*MyArray<bool,\s*42>
  TestA
  TestB
My/TypeParamTest/0\.  # TypeParam = (VeryLo{245}|class VeryLo{239})\.\.\.
  TestA
  TestB
My/TypeParamTest/1\.  # TypeParam = int\s*\*( __ptr64)?
  TestA
  TestB
My/TypeParamTest/2\.  # TypeParam = .*MyArray<bool,\s*42>
  TestA
  TestB
MyInstantiation/ValueParamTest\.
  TestA/0  # GetParam\(\) = one line
  TestA/1  # GetParam\(\) = two\\nlines
  TestA/2  # GetParam\(\) = a very\\nlo{241}\.\.\.
  TestB/0  # GetParam\(\) = one line
  TestB/1  # GetParam\(\) = two\\nlines
  TestB/2  # GetParam\(\) = a very\\nlo{241}\.\.\.
"

======================================================================
FAIL: testWithFilterFlags (__main__.GTestListTestsUnitTest)
Tests that --gtest_list_tests takes into account the
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_list_tests_unittest.py", line 203, in testWithFilterFlags
    other_flag='--gtest_filter=Foo*')
  File "/dev/shm/gtest_mut/gtest_src/googletest/test/gtest_list_tests_unittest.py", line 166, in RunAndVerify
    expected_output_re.pattern)))
AssertionError: None is not true : when gtest_list_tests is 1, the output of "--gtest_list_tests --gtest_filter=Foo*" is "",
which does not match regex "FooDeathTest\.
  Test1
Foo\.
  Bar1
  Bar2
  DISABLED_Bar3
FooBar\.
  Baz
FooTest\.
  Test1
  DISABLED_Test2
  Test3
"

----------------------------------------------------------------------
Ran 4 tests in 0.561s

FAILED (failures=3)

44/60 Test #22: gtest-filepath_test .....................   Passed    0.02 sec
45/60 Test #44: gtest-death-test_ex_catch_test ..........   Passed    0.02 sec
      Start  4: gmock-generated-actions_test
      Start 21: gtest_environment_test
      Start  2: gmock-cardinalities_test
      Start 39: gtest_throw_on_failure_ex_test
46/60 Test  #4: gmock-generated-actions_test ............   Passed    0.00 sec
47/60 Test #21: gtest_environment_test ..................   Passed    0.00 sec
48/60 Test  #2: gmock-cardinalities_test ................   Passed    0.00 sec
49/60 Test #39: gtest_throw_on_failure_ex_test ..........   Passed    0.00 sec
      Start  3: gmock_ex_test
      Start 28: gtest-options_test
      Start 18: gmock-more-actions_no_exception_test
      Start 10: gmock-more-actions_test
50/60 Test #18: gmock-more-actions_no_exception_test ....   Passed    0.00 sec
51/60 Test  #3: gmock_ex_test ...........................   Passed    0.01 sec
52/60 Test #28: gtest-options_test ......................   Passed    0.00 sec
53/60 Test #10: gmock-more-actions_test .................   Passed    0.00 sec
      Start 34: gtest_prod_test
      Start  6: gmock-generated-internal-utils_test
      Start 27: gtest_no_test_unittest
      Start 26: gtest-message_test
54/60 Test #27: gtest_no_test_unittest ..................   Passed    0.00 sec
55/60 Test #26: gtest-message_test ......................   Passed    0.00 sec
56/60 Test #34: gtest_prod_test .........................   Passed    0.00 sec
57/60 Test  #6: gmock-generated-internal-utils_test .....   Passed    0.00 sec
      Start 25: gtest_main_unittest
      Start 32: gtest_premature_exit_test
      Start 23: gtest-linked_ptr_test
58/60 Test #23: gtest-linked_ptr_test ...................   Passed    0.00 sec
59/60 Test #32: gtest_premature_exit_test ...............   Passed    0.00 sec
60/60 Test #25: gtest_main_unittest .....................   Passed    0.00 sec

90% tests passed, 6 tests failed out of 60

Total Test time (real) =   4.88 sec

The following tests FAILED:
         40 - gtest-typed-test_test (OTHER_FAULT)
         41 - gtest_unittest (OTHER_FAULT)
         45 - gtest_no_rtti_unittest (OTHER_FAULT)
         54 - gtest_list_tests_unittest (Failed)
         55 - gtest_output_test (Failed)
         60 - gtest_xml_output_unittest (Failed)
EOF
exit 1
`;
    }
}

// TODO: this test is missing a void test() thus it is doing nothing
class TestCaseDetection : SimpleFixture {
    override string scriptTest() {
        return "#!/bin/bash
cat <<EOF
Running main() from gtest_main.cc
[==========] Running 4 tests from 1 test case.
[----------] Global test environment set-up.
[----------] 4 tests from MessageTest
[ RUN      ] MessageTest.CopyConstructor
[       OK ] MessageTest.CopyConstructor (0 ms)
[ RUN      ] MessageTest.ConstructsFromCString
[       OK ] MessageTest.ConstructsFromCString (0 ms)
[ RUN      ] MessageTest.StreamsFloat
[       OK ] MessageTest.StreamsFloat (0 ms)
[ RUN      ] MessageTest.StreamsDouble
[       OK ] MessageTest.StreamsDouble (0 ms)
[----------] 4 tests from MessageTest (0 ms total)

[----------] Global test environment tear-down
[==========] 4 tests from 1 test case ran. (0 ms total)
[  PASSED  ] 4 tests.
EOF
exit 1
";
    }
}

class ShallDetectAllTestCases : TestCaseDetection {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-builtin", "gtest"])
            .addPostArg(["--test-timeout", "10000"])
            .run;

        foreach (l; [
            "MessageTest.CopyConstructor",
            "MessageTest.ConstructsFromCString",
            "MessageTest.StreamsFloat",
            "MessageTest.StreamsDouble"]) {
            testConsecutiveSparseOrder!SubStr([
                "Found new test case",
                l,
            ]).shouldBeIn(r.stdout);
        }
        // dfmt on

        testConsecutiveSparseOrder!SubStr(["Resetting alive mutants"]).shouldNotBeIn(r.stdout);
    }
}

class ShallResetOnNewTestCases : TestCaseDetection {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        immutable conf_f = (testEnv.outdir ~ "conf.toml").toString;

        File(conf_f, "w").write(`[mutant_test]
detected_new_test_case = "resetAlive"
`);

        // dfmt off
        auto r0 = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-builtin", "gtest"])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on

        immutable scriptGTestSuiteAddOne = "#!/bin/bash
cat <<EOF
Running main() from gtest_main.cc
[==========] Running 4 tests from 1 test case.
[----------] Global test environment set-up.
[----------] 4 tests from MessageTest
[ RUN      ] MessageTest.CopyConstructor
[       OK ] MessageTest.CopyConstructor (0 ms)
[ RUN      ] MessageTest.ConstructsFromCString
[       OK ] MessageTest.ConstructsFromCString (0 ms)
[ RUN      ] MessageTest.StreamsFloat
[       OK ] MessageTest.StreamsFloat (0 ms)
[ RUN      ] MessageTest.StreamsDouble
[       OK ] MessageTest.StreamsDouble (0 ms)
[ RUN      ] MessageTest.StreamsDouble2
[       OK ] MessageTest.StreamsDouble2 (0 ms)
[----------] 4 tests from MessageTest (0 ms total)

[----------] Global test environment tear-down
[==========] 4 tests from 1 test case ran. (0 ms total)
[  PASSED  ] 4 tests.
EOF
exit 1
";

        File(test_script, "w").write(scriptGTestSuiteAddOne);
        makeExecutable(test_script);

        // dfmt off
        auto r1 = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addArg(["-c", conf_f])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-builtin", "gtest"])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!SubStr(["Resetting alive mutants"]).shouldBeIn(r1.stdout);
    }
}

class DroppedTestCases : TestCaseDetection {
    auto run(ref TestEnv testEnv, string[] extra_args) {
        // dfmt off
        auto r0 = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-builtin", "gtest"])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on

        immutable scriptGTestSuiteDropOne = "#!/bin/bash
cat <<EOF
Running main() from gtest_main.cc
[==========] Running 4 tests from 1 test case.
[----------] Global test environment set-up.
[----------] 4 tests from MessageTest
[ RUN      ] MessageTest.CopyConstructor
[       OK ] MessageTest.CopyConstructor (0 ms)
[ RUN      ] MessageTest.ConstructsFromCString
[       OK ] MessageTest.ConstructsFromCString (0 ms)
[ RUN      ] MessageTest.StreamsFloat
[       OK ] MessageTest.StreamsFloat (0 ms)
[----------] 4 tests from MessageTest (0 ms total)

[----------] Global test environment tear-down
[==========] 4 tests from 1 test case ran. (0 ms total)
[  PASSED  ] 4 tests.
EOF
exit 1
";

        File(test_script, "w").write(scriptGTestSuiteDropOne);
        makeExecutable(test_script);

        // dfmt off
        auto r1 = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(extra_args)
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-case-analyze-builtin", "gtest"])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on
        return r1;
    }
}

class ShallDoNothingWhenDetectDroppedTestCases : DroppedTestCases {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);
        auto r1 = run(testEnv, null);

        testConsecutiveSparseOrder!SubStr([
                "Detected test cases that has been removed",
                ]).shouldNotBeIn(r1.stdout);
    }
}

class ShallRemoveDetectDroppedTestCases : DroppedTestCases {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);
        auto r1 = run(testEnv, [
                "-c", (testData ~ "config/remove_dropped_test_cases.toml").toString
                ]);

        testConsecutiveSparseOrder!SubStr([
                "Detected test cases that has been removed",
                "MessageTest.StreamsDouble",
                ]).shouldBeIn(r1.stdout);
    }
}

class ShallKeepTheTestCaseResultsLinkedToMutantsWhenReAnalyzing : DatabaseFixture {
    override void test() {
        import dextool.plugin.mutate.backend.database.type;
        import dextool.plugin.mutate.backend.type;

        mixin(EnvSetup(globalTestdir));
        auto db = precondition(testEnv);

        db.updateMutation(MutationId(1), Mutation.Status.killed,
                5.dur!"msecs", [TestCase("tc_1")]);
        // verify pre-condition that test cases exist in the DB
        auto r0 = makeDextoolReport(testEnv, testData.dirName).addArg([
                "--section", "tc_stat"
                ]).run;
        testConsecutiveSparseOrder!SubStr(["| 100        | 2     | tc_1     |"]).shouldBeIn(
                r0.stdout);

        // Act
        makeDextoolAnalyze(testEnv).addInputArg(testData ~ "report_one_ror_mutation_point.cpp").run;

        // Assert that the test cases are still their
        auto r1 = makeDextoolReport(testEnv, testData.dirName).addArg([
                "--section", "tc_stat"
                ]).run;
        testConsecutiveSparseOrder!SubStr(["| 100        | 2     | tc_1     |"]).shouldBeIn(
                r1.stdout);
    }
}

class ShallRetrieveOldestMutant : DatabaseFixture {
    override void test() {
        import dextool.plugin.mutate.backend.database.type;
        import dextool.plugin.mutate.backend.type;

        mixin(EnvSetup(globalTestdir));
        auto db = precondition(testEnv);

        // arrange. moving all mutants except `expected` forward in time.
        const expected = 2;
        Thread.sleep(1.dur!"seconds");
        foreach (const id; db.getAllMutationStatus.filter!(a => a != expected))
            db.updateMutationStatus(id, Mutation.Status.killed, Yes.updateTs);

        // act
        const oldest = db.getOldestMutants([EnumMembers!(Mutation.Kind)], 1);

        // assert
        oldest.length.shouldEqual(1);
        oldest[0].id.shouldEqual(expected);
    }
}

class ShallUpdateMutationCounter : DatabaseFixture {
    override void test() {
        import dextool.plugin.mutate.backend.database.type;
        import dextool.plugin.mutate.backend.type;

        mixin(EnvSetup(globalTestdir));
        auto db = precondition(testEnv);

        // arrange
        const mid = MutationId(2);
        const mst_id = db.getMutationStatusId(mid).get;

        // act. should be the highest count not oldest
        db.updateMutation(MutationId(10), Mutation.Status.killed, 1.dur!"seconds", null);
        db.updateMutation(mid, Mutation.Status.killed, 1.dur!"seconds", null);
        db.updateMutation(mid, Mutation.Status.killed, 1.dur!"seconds", null);

        // assert
        auto hardest = db.getHardestToKillMutant([EnumMembers!(Mutation.Kind)],
                Mutation.Status.killed, 1);
        hardest.length.should == 1;
        auto hr = hardest[0];
        mst_id.should == hr.statusId;
    }
}

class ShallResetMutationCounter : DatabaseFixture {
    override void test() {
        import dextool.plugin.mutate.backend.database.standalone;
        import dextool.plugin.mutate.backend.database.type;
        import dextool.plugin.mutate.backend.type;

        mixin(EnvSetup(globalTestdir));
        auto db = precondition(testEnv);

        // arrange
        const mid = MutationId(2);
        const mst_id = db.getMutationStatusId(mid).get;
        db.updateMutation(MutationId(10), Mutation.Status.killed, 1.dur!"seconds", null);
        db.updateMutation(mid, Mutation.Status.killed, 1.dur!"seconds", null);
        db.updateMutation(mid, Mutation.Status.killed, 1.dur!"seconds", null);

        // act
        db.updateMutation(mid, Mutation.Status.killed, 1.dur!"seconds", null,
                Database.CntAction.reset);

        // assert
        auto hardest = db.getHardestToKillMutant([EnumMembers!(Mutation.Kind)],
                Mutation.Status.killed, 1);
        hardest.length.should == 1;
        auto hr = hardest[0];
        mst_id.should.not == hr.statusId;
    }
}

class ShallStopAtMaxRuntime : SimpleFixture {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-timeout", "10000"])
            .addPostArg(["--max-runtime", "5 msecs"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!SubStr([`Max runtime of`, `Done!`]).shouldBeIn(r.stdout);
    }
}

class ShallTestMutantsOnSpecifiedLines : SimpleFixture {
    override void test() {
        import std.path : relativePath;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-timeout", "10000"])
            .addPostArg(["-L", program_cpp.relativePath(workDir.toString) ~ ":11-14"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!Re([
                `.*Found 1 mutant.*program.cpp:11`,
                `.*Found 1 mutant.*program.cpp:13`
                ]).shouldBeIn(r.stdout);
        testAnyOrder!Re([`info:.*from 'case 3:`, `info:.*from 'case 1:`,]).shouldBeIn(r.stdout);
    }

    override string programFile() {
        return (testData ~ "dcc_dc_switch1.cpp").toString;
    }
}

class ShallTestMutantsInDiff : SimpleFixture {
    override void test() {
        import std.path : relativePath;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programFile).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-timeout", "10000"])
            .addPostArg(["--diff-from-stdin"])
            .setStdin(readText(programFile ~ ".diff"))
            .run;
        // dfmt on

        testConsecutiveSparseOrder!Re([
                `.*Found 1 mutant.*dcc_dc_switch1.cpp:12`,
                ]).shouldBeIn(r.stdout);
        testAnyOrder!Re([`info:.*from 'case 1:`, `info:.*killed`,]).shouldBeIn(r.stdout);
    }

    override string programFile() {
        return (testData ~ "dcc_dc_switch1.cpp").toString;
    }
}

class ShallStopAfterNrAliveMutantsFound : SimpleFixture {
    override void test() {
        import std.path : relativePath;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", "/bin/true"])
            .addPostArg(["--test-timeout", "10000"])
            .addPostArg(["--max-alive", "3"])
            .addPostArg(["-L", program_cpp.relativePath(workDir.toString) ~ ":8-18"])
            .run;

        testConsecutiveSparseOrder!Re([
                `info:.*alive`,
                `info:.*Found 1/3 alive mutants`,
                `info:.*alive`,
                `info:.*Found 2/3 alive mutants`,
                `info:.*alive`,
                `info:.*Found 3/3 alive mutants`,
                ]).shouldBeIn(r.stdout);
        // dfmt on
    }

    override string programFile() {
        return (testData ~ "dcc_dc_switch1.cpp").toString;
    }
}
