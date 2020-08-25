# Dextool Mutate

Dextool's plugin for mutation testing of C/C++ projects. It can help you design
new tests and evaluate the quality of existing tests by measuring their ability
to detect artificially injected faults.

## Features

* 💉 Supports conventional mutation operators:
    [AOR, ROR, DCC, DCR, LCR, COR, SDL](https://github.com/joakim-brannstrom/dextool/blob/master/plugin/mutate/doc/design/mutations.md).
* 📈 Provides multiple [report](#report) formats (Markdown, Compiler warnings,
  JSON, HTML).
* 💪 Detects "useless" test cases that do not kill any mutants.
* 💪 Detects "redundant" test cases that kill the same mutants.
* 💪 Detects "redundant" test cases that do not uniquely kill any mutants.
* 💪 Lists "near" test cases from which a new test can be derived to kill a
  surviving mutant of interest.
* 🔄 Supports [change-based mutation testing](#change-based) for fast feedback
  in a pull request workflow.
* 🐇 Can [continue](#incremental-mutation-test) from where a testing session
  was interrupted.
* 🐇 Allows multiple instances to be [run in parallel](#parallel-run).
* 🐇 Can reuse previous results when a subset of the SUT changes by only testing those changes (files for now).
* 🐇 Can automatically [rerun the mutations that previously survived](#re-test-alive)
    when new tests are added to the test suite.
* 🐇 Does automatic handling of infinite loops (timeout).
* 🐇 Detects that a file has been renamed and move the mutation testing result
  from the new filename.
* 🔨 Works with all C++ versions.
* 🔨 Works with C++ templates.
* 🔨 Integrates without modifications to the projects build system.
* 🔨 Lets a user modify it by using a SQLite database as intermediary storage.
* 🔨 Lets a user mark a mutant as [dont care](#mark-mutant).

# Mutation Testing

Mutation testing focus on determining the adequacy of a test suite. Code
coverage determine this adequacy by if the test suite has executed the system
under test. Mutation testing determine the adequacy by injecting syntactical
faults (mutants) and executing the test suite. If the test suite "fail" it is
interpreted as the syntactical fault (mutant) being found and killed by the
test suite (good).

The algorithm for mutation testing is thus:

 * inject one mutant.
 * execute the test suite.
 * if the test suite **failed** record the mutant as **killed** otherwise
   **alive**.

## Apply Mutation Testing a cmake Project

This section explains how to use Dextool Mutate to analyze a C++ project that
uses the CMake build system.

Note though that the Dextool work with any build system that is able to
generate a JSON compilation database.  It is just that CMake conveniently has
builtin support to generate those.  For other build systems there exists the
excellent [BEAR](https://github.com/rizsotto/Bear) tool that can spy on the
build process to generate such a database.

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
test_cmd = "./test.sh"
#test_cmd_dir = ["./build/test"]
build_cmd = "./build.sh"
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

## Test Phase Execution Flow

The test phase (dextool mutate test) use the configuration files content in the
following way when executing:

1. Upon start the configuration is checked for if `test_cmd_dir` is configured.
   If yes then the directories are scanned recursively for executables. Any
   executable found is assumed to be a test that should be executed. These are
   added to `test_cmd`.

For each mutant:
2. Execute `build_cmd`. If `build_cmd` returns an exit code != 0 the mutant is
   marked as `killedByCompiler`. It is **very** important that this script also
   build the test suite if such is required for executing the test cases.
3. Execute `test_cmd`. If any of the `test_cmd` return an exit code != 0 the
   mutant is recorded as killed. If multiple test commands is specified they
   will be executed in parallel.
4. If the mutant is killed and either `analyze_cmd` or `analyze_using_builtin`
   is configured the output from the executed `test_cmd` is passed on to these
   to extract the specific test cases that killed the mutant.

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
analyzer by writing `unstable:` to stdout.

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

Create a file `test_analyze.sh` that will identify passed and a failing test
from stdout/stderr:
```sh
#!/bin/bash
# The arguments are paths to stdout ($1) and stderr ($2).
# This script assumes that nothing is in stderr.

# Using a more complex while loop to avoid side effects such as trimming leading
# whitespace, interpreting backslash sequences, and skipping the trailing line
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

And configure dextool to use it. Either via CLI (`--test-case-analyze-cmd`) or
config:
```toml
analyze_cmd = "test_analyze.sh"
```

## Parallel Run <a name="parallel-run"></a>

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

Configure each instance appropriately. As if they would run the mutation
testing by them self. When you are done it should look something like this.

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

## Report <a name="report"></a>
To see the result of the mutation testing and thus specifically those that
survived it is recommended to user the preconfigured `--level alive` parameter.
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

## Re-test Alive Mutants <a name="re-test-alive"></a>

Lets say that we want to re-test the mutants that survived because new tests
have been added to the test suite. To speed up the mutation testing run we
don't want to test all mutants but just those that are currently marked as
alive.

This is achieved by changing the configuration file from doNothing to
resetAlive:
```toml
detected_new_test_case = "resetAlive"
```

It is recommended to also active the detection of dropped test cases and
re-execution of old mutants to further improve the quality of the mutation
score.

This retest all mutants that a test case that is removed killed.
```toml
detected_dropped_test_case = "remove"
```

This option re-test old mutants to see if anything has changed regarding the
test suite. Because dextool mutate can't "see" if a test case implementation
has changed and thus need to re-execute it the only way that is left is to
re-execute the mutants. Balance the number of mutants to test against how many
that exists.
```toml
oldest_mutants_nr = 10
```

## Incremental Mutation Testing <a name="incremental-mutation-test"></a>

The tool have support for testing only the changes to a program by reusing a
previous database containing mutation testning result.  All we have to do to
use this feature is to re-analyze the software. The tool will then remove all
the mutants for files that have changed.

## Change Based Testing for Pull Request Integration <a name="change-based"></a>

It is important to give fast feedback on a pull request and herein lies the
problem for mutation testing; it isn't fast. But a pull request usually only
touch a small part of a code base, a small diff. Change based testing mean that
only those mutants on the changed lines are tested.

The recommended way of integrating this support is via git diff as follows:

Analyze as usual.
```sh
dextool mutate analyze
```

But run the mutation testing on only those lines that changed:
```sh
git diff | dextool mutate test --diff-from-stdin --mutant lcr --max-runtime "10 minutes" --max-alive 10
```
The option `--max-runtime` and `--max-alive` add further speedups to by
limiting the execution to a "short time" or when there are "too many" alive
mutants.

And at the end a report for the user:
```sh
git diff | dextool mutate report --diff-from-stdin --section summary --mutant lcr --style html
# use json to get a handy mutation score for the diff that can be written back
# to the pull request
git diff | dextool mutate report --diff-from-stdin --section summary --mutant lcr --style json
```

## Mark a Mutant as Dont Care <a name="mark-mutant"></a>

There are two ways of marking a mutant to the tool as "don't care". These are
either via a source code annotation or by attaching a forced mutation status to
a mutation ID.

There are three flavors of the annotation.

 * `// NOMUT`. All mutants on the line are marked.
 * `// NOMUT (tag)`. The tag is used to group the annotations together in the HTML report.
    A good group could be "trace log".
 * `// NOMUT (tag) a comment`. The comment is added to the HTML report as a separate column.

All mutants that are marked as `NOMUT` will be subtracted from the total when
final mutation score is calculated. Additional fields in the statistics are
also added which highlight how many of the total that are annotated as `NOMUT`.
This is to make it easier to find and react if it where to become too many of
them.

The other way is by the administration interface. For example:
```sh
dextool mutate admin --operation markMutant --id 42 --to-status killed --rationale "Trace logging"
# and to see them
dextool mutate report --section marked_mutants
```

A marked mutant will affect the mutation score in the same way as the status it
is set to would. In the above example the mutant would count as killed.

The ID can be found by either looking in the report of all mutants/alive/killed
via the `--section` report or easier by checking the HTML report.

Each of these approaches have there pro and con. The basic problem that both
approaches try to tackles in different ways is how to keep the annotation when
the source code is changed. It is obvious that the source code annotation is
easier to keep suppressing the correct mutants. The administration interface is
unable to do that if the source code file is changed. If that happens the
`markMutant` will be reported during the analyze phase as being lost.

Source code annotations:

 * Pro: stable when the source code is changed.
 * Con: ugly because the source code needs to be annotated. By using the
   tag+comment the ugliness can be reduced by providing valuable information
   for why the mutant is not killed.
 * Con: all mutants on the line are marked as `NOMUT` thus unable to mark only
   one/a few. Low precision.

Administration interface:

 * Pro: no changes to the source code.
 * Pro: high precision when marking a mutant because only the specific mutant
   that is marked will be affected.
 * Con: loses its mark when the source code file is changed. Requires that the
   marking is re-applied manually.

# Code Coverage

It may be interesting to compare mutation testing results with code coverage.
To measure code coverage for the Google Test project, build it with:
```sh
cmake -DCMAKE_CXX_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_C_FLAGS="-fprofile-arcs -ftest-coverage" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-arcs -ftest-coverage" -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
```

To generate a HTML coverage report:
```sh
lcov -c --gcov-tool /usr/bin/gcov -d . --output-file app.info
genhtml app.info -o html
```
