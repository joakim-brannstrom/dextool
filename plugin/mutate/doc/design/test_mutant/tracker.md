# SPC-plugin_mutant_track_test_case
partof: SPC-plugin_mutant_test_mutant
###

The plugin shall activate the *test case tracker* functionality when the *CLI* is *test case analyzer command*.

Requirements for the *user supplied test case tracker*:
 * The plugin shall associate the output from executing the *user supplied test case tracker* to the killed mutant when a mutant is killed.
 * The plugin shall as arguments to *user supplied test case tracker* use *stdout.log* and *stderr.log* when executing the *user supplied test case tracker*.

**Note**: *stdout.log* and *stderr.log* are in the current implementation files but it could be changed in the future.

The plugin shall cleanup the temporary directory containing *stdout.log* and *stderr.log* when a mutant test is finalized.

## Draft Requirements and design

The user should be able to activate multiple test case trackers to be used at the same time. Both builtin and external.

This is because there may be a test suite that uses google test, CTest and python unittest framework.
To find the test cases it needs to go through multiple parsers in this case to ensure it is found.

Another common scenario is a *gtest* + *segfault*. When a mutation result in a segmentation fault there may be nothing besides a segmentation fault message printed.
If only a gtest tracker is used then there wont be any association between the test binary that segfaulted and the mutation.
This is solved by allowing multiple test case trackers.

## Design

The intention is to find test cases that *should* have killed mutants that survived and present those to the user. This makes it easier for the user to update a test suite to kill the mutant.

Let the plugin track what test cases kill what mutant. There will probably be multiple test cases for each mutant. This creates a mapping between test cases and mutants.

This information about what test cases killed what mutant can then be used as suggestions to the user for what test cases that can be updated to kill alive mutants.

A simple way of doing this is to just report all test cases associate with a mutation point.

## Musings

This is a *variant*, another approach, to using coverage.

This approach do not require that the target code can be compiled and executed with coverage.
This is *probably* information that the user would like either way.

A negative thing is that this would require the user to finish testing most of the mutants to get this information.

# SPC-plugin_mutate_track_gtest
partof: SPC-plugin_mutant_track_test_case
###

The plugin shall parse the output from the test suite when a mutant is killed and the *test case tracker* is gtest.

The plugin shall find the test cases that failed.

# TST-plugin_mutate_track_gtest
partof: SPC-plugin_mutate_track_gtest
###

TODO

## Example Test Data

```
Running main() from gtest_main.cc
[==========] Running 17 tests from 1 test case.
[----------] Global test environment set-up.
[----------] 17 tests from MessageTest
[ RUN      ] MessageTest.DefaultConstructor
/home/joker/src/cpp/googletest/googletest/test/gtest-message_test.cc:48: Failure
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
[  PASSED  ] 16 tests.
[  FAILED  ] 1 test, listed below:
[  FAILED  ] MessageTest.DefaultConstructor

 1 FAILED TEST
```

# SPC-plugin_mutate_track_ctest
partof: SPC-plugin_mutate_track_test_case
###

TODO: add req

# SPC-plugin_mutant_reset_alive
partof: REQ/SPC/TST-short text
###

The plugin shall reset alive mutants to unknown when new test cases are detected.

## Why?

This automates the process from the users perspective. Before this functionality where added a user had to manually reset the mutants.

It thus makes it easier to integrate in a continuous integration workflow.
