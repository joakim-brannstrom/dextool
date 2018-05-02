# Plugin mutate

This is the *mutate* plugin that can perform mutation testing on a program.

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
