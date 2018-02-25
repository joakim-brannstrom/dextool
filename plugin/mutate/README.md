# Dextool Mutate

The Dextool mutation testing plugin. 

## Overview

Dextool's plugin for mutation testing of C/C++ projects. It can help you design new tests and evaluate the quality of existing  tests.

### Features

TODO: List supported mutation operators etc.

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

Suppose the source code is in ... and the test code is elsewhere. Use the ``--restrict`` option to specify what to analyze:
```sh
dextool mutate analyze --compile-db compile_commands.json --restrict .. -- -D_POSIX_PATH_MAX=1024
```

Create a file ``tester.sh`` that runs the entire test suite when invoked:
```sh
#!/bin/bash
set -e
make test ARGS="-j$(nproc)"
```

Create a file ``compile.sh`` that builds the project when invoked:
```sh
#!/bin/bash
set -e
make -j$(nproc)
```

Make them executable so they can be used by dextool:
```sh
chmod 755 tester.sh
chmod 755 compile.sh
```

Start the mutation testing:
```sh
dextool mutate test --mutant-test ./tester.sh --mutant-compile ./compile.sh --restrict ..
```

It is possible to run multiple `test` against the same database.
Just make sure they don't mutate the same source code.

Generate the mutation testing result:
```sh
dextool mutate report --restrict .. --level alive --mutant lcr
```

It may be interesting to compare the mutation testing results with the code coverage. To measure code coverage, build the Google test project with:
```sh
cmake -DCMAKE_CXX_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_C_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-arcs -ftest-coverage" -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
```

Generate a HTML coverage report with:
```sh
lcov -c --gcov-tool /usr/bin/gcov -d . --output-file app.info
genhtml app.info -o html
```

# Administration

To get the files in the database:
```sh
sqlite3 dextool_mutate.sqlite3 "select * from files"
```

The different states a mutant are found in Mutation.Kind.

Reset all mutations of a kind to unknown which forces them to be tested again:
```sh
sqlite3 dextool_mutate.sqlite3 "update mutation SET status=0 WHERE mutation.kind=FOO"
```
