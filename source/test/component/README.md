# Introduction

This directory contains component tests for dextool.
The idea is that individual unit tests are spread out in the program. As it
should be in idiomatic D.

But the testing of multiple components are kept here. For the following reasons:
 - I foresee that the component tests will increase the unit test time.
   By keeping them all in one place it is easy to split the "unit tests" from
   the "component tests" in different binaries.
 - Component tests are by definition testing a larger scope than unit tests.

# Definitions

## Unit tests
Tests in a D module. It can be everything from individual functions to multiple
classes. But it must be within the same module.
test/ut_main.d

## Component tests
Functional tests of multiple D modules.
test/ut_main.d

## Integration tests
Test the binaries behavior. Example would be "golden file"-tests.
test/external_main.d
