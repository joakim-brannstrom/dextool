# vim: filetype=markdown

This file contains information useful to a developer of deXtool.

# Setup
Compared to a normal installation of deXtool a developer have additional needs
such as compiling a full debug build (contracts activated) and compiling the
tests.

Example:
```sh
mkdir build
cd build
# to run with coverage add -DTEST_WITH_COV=ON. Coverage is found in build/coverage
cmake -Wdev -DCMAKE_BUILD_TYPE=Debug -DBUILD_TEST=ON ..
```

This gives access to the make target _test_.

To run the tests:
```sh
# build and run the unittests
make check

# build and run the integration tests
make check_integration
```

# Plugin Test Strategy

## C/C++ Test Double Generator
The strategy for the test doubles are divided in three stages.

1. Test code generation for different aspects of the languages.
    The focus isn't on the functional aspects but rather that the generated
    test doubles are "correct". Correct as in C/C++ code that compiles and
    "looks good" to a human.
2. Test the parameters and other type of user defined input.
    How it affects generated test doubles.
3. Test the function aspects of the generated test doubles.
    Does the adapter work?
    Is the generated google mock definition possible to use with the adapter?
    Is the behavior of the test double what the user need?

# Design of Component Tests

The idea is that individual unit tests are spread out in the program. As it
should be in idiomatic D.

The testing of multiple components are to be kept separated from the unit
tests. For the following reasons:
 - I foresee that the component tests will increase the time it takes to run
   the whole test suite. By keeping component tests in one place it is easy to
   split them off to a separate binary to enable a fast write-compile-test
   cycle with "fast" tests while keeping the "slow" tests for the automated CI
   of PR's.
 - Unit tests are placed within the tested unit, while component tests does not
   fit inside a singe unit.

# Definitions

## Unit tests
Tests in a D module. It can be everything from individual functions to multiple
classes. But it must be within the same module.

 - See plugin/xyz/ut_main.d

## CI
Continues Integration

## Component tests
Functional tests of multiple D modules.

 - See source/test/component

## Integration tests
Test the final binaries behavior from the users perspective. Example would be
"golden file"-tests.

 - See plugin/xyz/test/integration.d
 - See test/integration_main.d

## PR

Pull Request
