This directory contains examples of how to use the mutate plugin.

It assumes that dextool has been installed and is available in the PATH.

# Test Code Snippets

This is an example of how to do mutation testing on small code snippets. It assumes that no dedicated build system or testing framework is used.

The root of the examples are [found here](triangle).

It uses makefiles for the integration with dextool thus to run mutation testing you would do:
```sh
make all
```

# Complex Project

This is an example of how to do mutation testing on the [Google Test project](https://github.com/google/googletest). A note here is that this also show how to use dextool together with cmake.

The root of the examples are [found here](gtest).

First we need to do some basic setup such as cloning the repo.

 * [1 setup](gtest/1_setup.sh)

The mutation testing is separated in three phases, analyze/test/report.

The analyze phase analyze the source code for mutants. This means that the analyze phase has to be re-executed when the source code change. Dextool warn when you need to do this.

 * [2 analyze](gtest/2_analyze.sh)

The test phase is time consuming. Multiple instances can be ran in parallell if they all use the same underlying database.

 * [3 test](gtest/3_test.sh)

Reporting can be performed whenever you want.

 * [4 report](gtest/4_report.sh)

# Incremental Mutation Testing

This example demonstrate the incremental mutatino testing capabilities of dextool.

Note that the initial test suite has full branch coverage and high MC/DC coverage but even though it do have this there are still a critical bug lurking in the shadows.

The scenario is a developer using mutation testing to improve the test suites effectiveness. At the end it finds the bug in the implementation. Although a bit contrieved it do show the impact different mutation operators have on the test suite when trying to verify an implementation.

To run the demo:
```
cd algol_test
./run_demo_0.sh
./run_demo_1.sh
./run_demo_2.sh
./run_demo_3.sh
```

Each step in the demo generate a html report at `html/index.html`.

To see the capability of dextool to detect when test cases are removed and then re-verify those mutants that the test cases killed one can run this sequence:
```sh
./run_demo_0.sh
./run_demo_1.sh
./run_demo_0.sh
```

It is a synthetic emulation of adding and removing a test case.
