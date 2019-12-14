# Dextool Mutate

Dextool's plugin for mutation testing of C/C++ projects. It can help you design new tests and evaluate the quality of existing tests by measuring their ability to detect artificially injected faults.

## Features

* Provides support for conventional mutation operators: AOR, ROR, DCC, DCR, LCR, COR, SDL.
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
* Detect test cases that do not kill any mutants. These test cases most *probably* do not verify anything.
* Detect test cases that kill the same mutants. These is an indication of redundant test cases.

# Mutation Testing

This section explains how to use Dextool Mutate to analyze a C++ project that uses the CMake build system.

Note though that the Dextool work with any build system that is able to generate a JSON compilation database.
It is just that CMake conveniently has builtin support to generate those.
For other build systems there exists the excellent [BEAR](https://github.com/rizsotto/Bear) tool that can spy on the build process to generate such a database.

The [Google Test project](https://github.com/google/googletest) is used as an example.

Obtain the project you want to analyze:
```sh
git clone https://github.com/google/googletest.git
cd googletest
```

Generate a JSON compilation database for the project:
```sh
mkdir build
pushd build
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
make
popd
```

Create a configuration file:
```sh
dextool mutate admin --init
```

Open the config file and change the following fields:
```toml
[workarea]
restrict = ["googlemock/include", "googlemock/src", "googletest/include", "googletest/src"]
[compiler]
extra_flags = [ "-D_POSIX_PATH_MAX=1024" ]
[compile_commands]
search_paths = ["./build/compile_commands.json"]
[mutant_test]
test_cmd = "test.sh"
build_cmd = "build.sh"
analyze_using_builtin = ["gtest"]
```

Generate a database of all mutation points:
```sh
dextool mutate analyze
```

Create a file `build.sh` that will build the subject under test when invoked:
```sh
#!/bin/bash
set -e
cd build
make -j$(nproc)
```

Create a file `test.sh` that will run the entire test suite when invoked:
```sh
#!/bin/bash
set -e
cd build
ctest --output-on-failure
```

Make the files executable so they can be used by dextool:
```sh
chmod 755 build.sh test.sh
```

Run the mutation testing on the LCR mutants:
```sh
dextool mutate test --mutant lcr
```

For more examples [see here](examples).

## Custom Test Analyzer

Dextool need some help to understand the output from the test suite.

To be able to find test cases that kill zero mutants, detect new test cases and
dropped test cases it needs to *find* all these test cases at the beginning
when it is measuring the performance of the test suite. This is why the
`passed:` is important.

To be able to map which test case killed which mutant it needs help finding the
test cases that failed when the mutant where injected. This is where the
`failed:` part comes in

To be able to test a mutant again because the test suite is unstable when it is
executed on the injected mutant it needs some help. This is signaled from the
analyser by writing writing `unstable:` to stdout.

The requirement on the script is that it should parse the files that contains
the output from the test suite. These are passed as argument one and two to the
script.

The analyzer should write to stdout with the following pattern for each test case:
 * passed test: `passed:<name of test>`
 * failed test: `failed:<name of test>`
 * unstable test: `unstable:<name of test>`

One line per test case.

Assume we have a test framework that generates results to stdout.

Execute some tests and copy the stdout result to a file named `stdout.txt`.

Example:

```sh
# Processing test cases.
(Passed) OnePlusOne
(Failed) TwoPlusTwo
test.c:6: Fail
      Expected: Add(2, 2)
      Which is: 4
To be equal to: 5
(Passed) TestStuff
# 3 tests processed. Summary:
# PASSED: 2
# FAILED: 1
```

Create a file `test_analyze.sh` that will identify passed and a failing test from stdout/stderr:
```sh
#!/bin/bash
# The arguments are paths to stdout ($1) and stderr ($2).
# This script assumes that nothing is in stderr.

# Using a more complex while loop to avoid side effects such as trimming leading
# whitespace, interpretting backslash sequences, and skipping the trailing line
# if it's missing a terminating linefeed. If these are concerns, you can do:
while IFS="" read -r L || [ -n "$L" ]; do
    echo "$L"|grep -h "(Failed)" > /dev/null
    if [[ $? -eq 0  ]]; then
        echo "failed:"$(echo "$L"|sed -e 's/(Failed)//')
    fi
    echo "$L"|grep -h "(Passed)" > /dev/null
    if [[ $? -eq 0  ]]; then
        echo "passed:"$(echo "$L"|sed -e 's/(Passed)//')
    fi
done < $1
```

Don't forget to make it executable:
```sh
chmod 755 test_analyze.sh
```

Check that the script works on your example:
```sh
touch stderr.txt
./test_analyze.sh stdout.txt stderr.txt
passed: OnePlusOne
failed: TwoPlusTwo
passed: TestStuff
```

And configure dextool to use it. Either via CLI (`--test-case-analyze-cmd`) or config:
```toml
analyze_cmd = "test_analyze.sh"
```

## Parallel Run

Parallel mutation testing is realized in dextool mutate by using the same
database in multiple instances via a symlink to a master database. Each
instance of dextool have their own source tree and build environment but the
database that is used is one and the same because of the symlink. This approach
scales reasonably well up to five parallel instances.

Lets say you want to setup parallel execution of googletest with two instances.
First clone the source code to two different locations.

```sh
git clone https://github.com/google/googletest.git gtest1
git clone https://github.com/google/googletest.git gtest2
```

Configure each instance appropriately. As if they would run the mutation testing
by them self. When you are done it should look something like this.

```sh
ls -a gtest1
build/ ..... .dextool_mutate.toml test.sh build.sh
ls -a gtest2
build/ ..... .dextool_mutate.toml test.sh build.sh
```

The next step is the analyze. This is only executed in one of the instances.
Lets say gtest1.

```sh
cd gtest1
dextool mutate analyze
```

Now comes the magic that makes it parallel. Create a symlink in gtest2 to the
database in gtest1.

```sh
cd gtest2
ln -s ../gtest1/dextool_mutate.sqlite3
```

Everything is now prepared for the parallel test phase. Start an instance of
dextool mutate in each of the directories.

```sh
cd gtest1
dextool mutate test
# new console
cd gtest2
dextool mutate test
```

Done!
This can significantly cut down on the test time.

You will now and then see output in the console about the database being
locked. That is as it should be. As noted earlier in this guide it scales OK to
five instances. This is the source of the scaling problem. The more instances
the more lock contention for the database.

## Results
To see the result of the mutation testing and thus specifically those that survived it is recommended to user the preconfigured `--level alive` parameter.
It prints a summary and the mutants that survived.

```sh
dextool mutate report --level alive --mutant lcr
```

But it is possible to in more detail control what sections are printed for the `--plain` printer.
Lets say we want to print the test case statistics, the summary and the killed mutants.
```sh
dextool mutate report --section tc_stat --section summary --section killed --section tc_killed_no_mutants --mutant lcr
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
