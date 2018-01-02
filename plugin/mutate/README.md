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
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..
dextool mutate --compile-db compile_commands.json --mode analyzer --restrict .. -- -D_POSIX_PATH_MAX=1024
```

Reconfigure and prebuild with the tests activated:
```sh
cmake -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
make
```

Create a file tester.sh with this content:
```sh
#!/bin/bash
set -e
make test ARGS="-j$(nproc)"
```

Create a file compile.sh with this content:
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
dextool mutate --mode test_mutants --mutant-test ./tester.sh --mutant-compile ./compile.sh --restrict ..
```

It is possible to run multiple `test_mutants` against the same database.
Just make sure they don't interfere with each other.

## Compiling Google Test with Coverage

It may be helpful to see the coverage of the Gtest test suite.

To compile with coverage:
```sh
cmake -DCMAKE_CXX_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_C_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-arcs -ftest-coverage" -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
```

To generate a HTML coverage report:
```sh
lcov -c --gcov-tool /usr/bin/gcov -d . --output-file app.info
genhtml app.info
```
