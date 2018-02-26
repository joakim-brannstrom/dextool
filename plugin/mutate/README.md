# Dextool Mutate

The Dextool mutation testing plugin. 

## Overview

Dextool's plugin for mutation testing of C/C++ projects. It can help you design new tests and evaluate the quality of existing  tests.

### Features

* Supported for conventional mutation operators: AOR, ROR, DCC, DCR, LCR, COR.
* Continue mutation testing from where it was interrupted.
* Run multiple mutation testing instances in parallel.
* Type aware ROR to reduce the number of equivalent mutants.
* Reuse a previous mutation run when a subset of the SUT changes by only testing those changes (files for now).
* Multiple report formats.
* SQLite database used as an intermediary storage which enables others to modify it if needed.
* Rerun e.g. the mutations that previously survived when new tests are added to the test suite.
* Automatic handling of infinite loops (timeout)
* Handles unstable infrastructure which reduces the wrongly classified timeout OR unstable test suites which have a variable execution time
* Works with all C++ versions
* Works with C++ templates
* Simple workflow
* Integrates without modifications to the project build system.

TODO: What are the selling points etc?

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
```

Suppose the source code is in ... and the test code is elsewhere. Use the `--restrict` option to specify what to analyze:
```sh
dextool mutate analyze --compile-db compile_commands.json --restrict .. -- -D_POSIX_PATH_MAX=1024
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
dextool mutate test --mutant-test ./tester.sh --mutant-compile ./compile.sh --restrict ..
```

Generate the mutation testing result:
```sh
dextool mutate report --restrict .. --level alive --mutant lcr
```

It may be interesting to compare mutation testing results with code coverage. To measure code coverage, build the Google test project with:
```sh
cmake -DCMAKE_CXX_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_C_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-arcs -ftest-coverage" -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
```

Generate a HTML coverage report with:
```sh
lcov -c --gcov-tool /usr/bin/gcov -d . --output-file app.info
genhtml app.info -o html
```

# Administration

Todo: exlain database concept.

It is possible to run multiple `test` against the same database.
Just make sure they don't mutate the same source code.

To get the files in the database:
```sh
sqlite3 dextool_mutate.sqlite3 "select * from files"
```

The different states a mutant are found in Mutation.Kind.

Reset all mutations of a kind to unknown which forces them to be tested again:
```sh
sqlite3 dextool_mutate.sqlite3 "update mutation SET status=0 WHERE mutation.kind=FOO"
```
