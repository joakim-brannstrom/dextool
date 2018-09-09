# Dextool Mutate

Dextool's plugin for mutation testing of C/C++ projects. It can help you design new tests and evaluate the quality of existing tests by measuring their ability to detect artificially injected faults.

## Features

* Provides support for conventional mutation operators: AOR, ROR, DCC, DCR, LCR, COR.
* Can continue from where a testing session was interrupted.
* Allows multiple instances to be run in parallel.
* Makes type aware ROR to reduce the number of equivalent mutants.
* Can reuse previous results when a subset of the SUT changes by only testing those changes (files for now).
* Provides multiple report formats (Markdown, compiler warnings, JSON).
* Lets a user modify it by using a SQLite database as intermediary storage.
* Can rerun e.g. the mutations that previously survived when new tests are added to the test suite.
* Does automatic handling of infinite loops (timeout).
* Works with all C++ versions.
* Works with C++ templates.
* Has a simple workflow.
* Integrates without modifications to the projects build system.

# Mutation Testing

This section explains how to use Dextool Mutate to analyze a C++ project. The tool works with any type of build system that is able to generate a JSON compilation database.

The [Google Test project](https://github.com/google/googletest) will be used as an example.

Obtain the project you want to analyze:
```sh
git clone https://github.com/google/googletest.git
cd googletest
```

Generate a JSON compilation database for the project:
```sh
mkdir build
cd build
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
make
```

Generate a database of all mutation points:
```sh
dextool mutate analyze --compile-db compile_commands.json --out .. --restrict ../googlemock/include --restrict ../googlemock/src --restrict ../googletest/include --restrict ../googletest/src -- -D_POSIX_PATH_MAX=1024
```

Create a file `tester.sh` that will run the entire test suite when invoked:
```sh
#!/bin/bash
set -e
ctest --output-on-failure -j4
```

Create a file `compile.sh` that will build the entire project when invoked:
```sh
#!/bin/bash
set -e
make -j$(nproc)
```

Create a file `test_analyze.sh` that will identify a failing test from stdout:
```sh
#!/bin/bash
# The binaries that failed
grep -h "(Failed)" $1 $2
```

Make the files executable so they can be used by dextool:
```sh
chmod 755 test.sh
chmod 755 compile.sh
chmod 755 test_analyze.sh
```

Run the mutation testing:
```sh
dextool mutate test --test ./test.sh --compile ./compile.sh --test-case-analyze-cmd ./test_analyze.sh --out .. --mutant lcr
```

Dextool has builtin support for Google Test which improves the tracking to the test case and file level. To use the builtin support, change the `--test-case-analyze-cmd ./test_analyze.sh` to `--test-case-analyze-builtin gtest --test-case-analyze-builtin ctest`

## Parallel Run

It is possible to run multiple instances of dextool the same database.
Just make sure they don't mutate the same source code.

## Results
To see the result of the mutation testing and thus specifically those that survived it is recommended to user the preconfigured `--level alive` parameter.
It prints a summary and the mutants that survived.

```sh
dextool mutate report --out .. --level alive --mutant lcr
```

But it is possible to in more detail control what sections are printed for the `--plain` printer.
Lets say we want to print the test case statistics, the summary and the killed mutants.
```sh
dextool mutate report --out .. --section tc_stat --section summary --section killed --mutant lcr
```

See `--section` for a specification of the supported sections.

## Re-test Alive Mutants

Lets say that we want to re-test the mutants that survived because new tests have been added to the test suite. To speed up the mutation testing run we don't want to test all mutants but just those that are currently marked as alive.

This can be achieved by resetting the status of the alive mutants to unknown followed by running the mutation testing again.

Example of resetting:
```sh
dextool mutate admin --mutant lcr --operation resetMutant --status alive
```

## Incremental Mutation Testing

The tool have support for testing only the changes to a program by reusing a previous database containing mutation testning result.
All we have to do to use this feature is to re-analyze the software. The tool will then remove all the mutants for files that have changed.

# Code Coverage

It may be interesting to compare mutation testing results with code coverage. To measure code coverage for the Google Test project, build it with:
```sh
cmake -DCMAKE_CXX_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_C_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-arcs -ftest-coverage" -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
```

To generate a HTML coverage report:
```sh
lcov -c --gcov-tool /usr/bin/gcov -d . --output-file app.info
genhtml app.info -o html
```
