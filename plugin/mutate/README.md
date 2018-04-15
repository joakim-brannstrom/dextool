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

# Mutation Testing of Google Test

This is an example of how to mutation test google test itself.
It assumes the current directory is _build_ which is then located the google test repo.

Create a database of all mutation points:
```sh
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
dextool mutate analyze --compile-db compile_commands.json --out .. --restrict ../googlemock/include --restrict ../googlemock/src --restrict ../googletest/include --restrict ../googletest/src -- -D_POSIX_PATH_MAX=1024
```

Create a file test.sh with this content:
```sh
#!/bin/bash
set -e
ctest --output-on-failure -j4
```

Create a file compile.sh with this content:
```sh
#!/bin/bash
set -e
make -j$(nproc)
```

Create the file test_analyze.sh with this content:
```sh
#!/bin/bash
# The binaries that failed
grep -h "(Failed)" $1 $2
```

Make them executable so they can be used by dextool:
```sh
chmod 755 test.sh
chmod 755 compile.sh
chmod 755 test_analyze.sh
```

Start mutation testing!!!!:
```sh
dextool mutate test --test ./test.sh --compile ./compile.sh --test-case-analyze-cmd ./test_analyze.sh --out .. --mutant lcr
```

Dextool have builtin support for GoogleTest which improves the tracking to the test case and file level.
Change the `--test-case-analyze-cmd ./test_analyze.sh` to `--test-case-analyze-builtin gtest --test-case-analyze-builtin ctest`

## Parallel Run

It is possible to run multiple instances of dextool the same database.
Just make sure they don't mutate the same source code.

## Results

To see the result:
```sh
dextool mutate report --out .. --level alive --mutant lcr
```

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
