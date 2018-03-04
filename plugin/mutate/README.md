# Dextool Mutate

The Dextool mutation testing plugin. 

## Overview

Dextool's plugin for mutation testing of C/C++ projects. It can help you design new tests and evaluate the quality of existing  tests.

### Features

* Provides support for conventional mutation operators: AOR, ROR, DCC, DCR, LCR, COR.
* Can continue from where a testing session was interrupted.
* Allows multiple instances to be run in parallel.
* Makes type aware ROR to reduce the number of equivalent mutants.
* Can reuse previous results when a subset of the SUT changes by only testing those changes (files for now).
* Provides multiple report formats.
* Lets a user modify it by using a SQLite database as intermediary storage.
* Can rerun e.g. the mutations that previously survived when new tests are added to the test suite.
* Does automatic handling of infinite loops (timeout).
* Works with all C++ versions.
* Works with C++ templates.
* Has a simple workflow.
* Integrates without modifications to the projects build system.

# Getting Started

If you are new to dextool, we suggest you to read the following:

* TODO: Something about compilation databases
* TODO: Something about mutation testing

## Mutation testing

### Using CMake

The [Google Test project](https://github.com/google/googletest) will be used as an example.

When setting up Dextool Mutate to analyze a CMake project, the typical workflow is to:
```sh
# Obtain the project
git clone https://github.com/google/googletest.git
cd googletest

# Create a directory to hold the build output:
mkdir build
cd build

# Generate a JSON compilation database and build scripts:
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
make

# Analyze the project:
dextool mutate analyze --compile-db compile_commands.json --out .. --restrict ../googlemock/include --restrict ../googlemock/src --restrict ../googletest/include --restrict ../googletest/src -- -D_POSIX_PATH_MAX=1024
```

Create a script `tester.sh` that runs the entire test suite when invoked:
```sh
#!/bin/bash
set -e
make test ARGS="-j$(nproc)"
```

Create a script `compile.sh` that builds the project when invoked:
```sh
#!/bin/bash
set -e
make -j$(nproc)
```

Make the scripts executable so they can be run by dextool:
```sh
chmod 755 tester.sh
chmod 755 compile.sh
```

Execute the mutation testing:
```sh
dextool mutate test --test ./tester.sh --compile ./compile.sh --out ..
```

Generate the mutation testing result:
```sh
dextool mutate report --out .. --level alive --mutant lcr
```

## Code Coverage

It may be interesting to compare mutation testing results with code coverage. To measure code coverage for the Google Test project; build it with:
```sh
cmake -DCMAKE_CXX_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_C_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-arcs -ftest-coverage" -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
```

Generate a HTML coverage report with:
```sh
lcov -c --gcov-tool /usr/bin/gcov -d . --output-file app.info
genhtml app.info -o html
```

# Re-test alive Mutants

Suppose the test suite is update.
In such a case it is very interesting to rerun the test suite to see if it kills any additional mutants.

To reset the alive LCR mutants and thus force them to be tested again (assumes that the database is the default name and in this directory):
```sh
dextool mutate admin --mutant lcr --status alive
```

Then the test subcommand can be used again.

# Multiple Instances

It is possible to run multiple `test` commands against the same database.
The trick to make it work is to have multiple build + source codes to mutate but point all `dextool mutate test` runs against the same database via the `--db` flag.
For a low number of instances where the compile + test time is *noticeable* the database lock contention wont be a problem.
