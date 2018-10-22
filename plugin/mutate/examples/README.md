This directory contains examples of how to use the mutate plugin.

It assumes that dextool has been installed and is available in the PATH.

# Test Code Snippets

This is an example of how to do mutation testing on small code snippets. It assumes that no dedicated build system or testing framework is used.

The root of the examples are [found here](triangle).

 * [1 setup](triangle/1_setup.sh)

# Complex Project

This is an example of how to do mutation testing on the [Google Test project](https://github.com/google/googletest).

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
