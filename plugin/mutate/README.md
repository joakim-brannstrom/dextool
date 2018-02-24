# Dextool Mutate

The Dextool mutation testing plugin. 

## Overview

Dextool's plugin for mutation testing of C/C++ projects. It can help you measure the test case quality, blabla.

### Features

TODO: List supported mutation operators etc.

# Getting Started

If you are new to the dextool framework or the mutation testing concept, we suggest you to read the following:

* TODO: Something about compilation databases
* TODO: Something about mutation testing

## Using Dextool mutate

### On a CMake project

Let's pick the [Google Test project](https://github.com/google/googletest) as an example.

When setting up Dextool to analyze a CMake project, the typical workflow is to:
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

Suppose you have the software under test in ... and the test code is elsewhere. Use the ``--restrict`` option to distinguish this when telling dextool what to analyze:
```sh
dextool mutate analyze --compile-db compile_commands.json --restrict .. -- -D_POSIX_PATH_MAX=1024
```

Create a file ``tester.sh`` with this content:
```sh
#!/bin/bash
set -e
make test ARGS="-j$(nproc)"
```

Create a file ``compile.sh`` with this content:
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

Start mutation testing:
```sh
dextool mutate test --mutant-test ./tester.sh --mutant-compile ./compile.sh --restrict ..
```

It is possible to run multiple `test` against the same database.
Just make sure they don't mutate the same source code.

To see the result:
```sh
dextool mutate report --restrict .. --level alive --mutant lcr
```

### On a makefile project

TODO: Add description

## Compiling Google Test with Coverage

It may be helpful to see the coverage of the Gtest test suite.

To compile with coverage:
```sh
cmake -DCMAKE_CXX_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_C_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-arcs -ftest-coverage" -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
```

To generate a HTML coverage report:
```sh
lcov -c --gcov-tool /usr/bin/gcov -d . --output-file app.info
genhtml app.info -o html
```

# Admin and other fun stuff

To get the files in the database:
```sh
sqlite3 dextool_mutate.sqlite3 "select * from files"
```

The different states a mutant are found in Mutation.Kind.

Reset all mutations of a kind to unknown which forces them to be tested again:
```sh
sqlite3 dextool_mutate.sqlite3 "update mutation SET status=0 WHERE mutation.kind=FOO"
```
