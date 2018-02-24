# Dextool Mutate

The Dextool mutatation testing plugin. 

## Overview

Dextool's plugin for mutation testing of C/C++ projects. It can help you measure the test case quality, blabla.

### Features

TODO: List supported mutation operators etc.

# Getting Started

If you are new to the dextool framework or the mutation testing concept, we suggest you to read the following:

* TODO: Something about compilation databases
* TODO: Something about mutation testing

## Using Dextool mutate

In this guide, the [Google Test project](https://github.com/google/googletest) will be used as an example.

### On a CMake project

When using Dextool mutate on a CMake project, the typical workflow starts with:
```sh
git clone https://github.com/google/googletest.git   # Obtain the google test project
cd googletest
mkdir build                                          # Create a directory to hold the build output.
cd build
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..          # Generate JSON compilation database and build scripts.
```

Suppose you have the software under test in ... and the test code elsewhere. The ``--restrict`` option separates subject code (to be mutated) from test code. Tell dextool what to analyze:
```sh
dextool mutate analyze --compile-db compile_commands.json --restrict .. -- -D_POSIX_PATH_MAX=1024
```

Reconfigure and prebuild with the tests activated:
```sh
cmake -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
make
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

Start mutation testing!!!!:
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
