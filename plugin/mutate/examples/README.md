This directory contains examples of how to use the mutate plugin.

It assumes that dextool has been installed and is available in the PATH.

# Simple and Easy

The [Google Test project](https://github.com/google/googletest) will be used as an example.

Example [found here](gtest).

This is an example of how to do mutation testing of googletest + googlemock.

[1 setup](gtest/1_setup.sh)

The mutation testing is separated in three phases, analyze/test/report.

 * [2 analyze](gtest/2_analyze.sh)
 * [3_test](gtest/3_test.sh)
 * [4 report](gtest/4_report.sh)
