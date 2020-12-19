# Embedded Systems

It can be a bit tricky to use mutation testing for embedded systems. The most
common problem is that the test framework that is used is a simple, custom made
framework. Dextool allow you, as the user, to write your own analyser of the
test suites output without changing dextool.

There is an additional feature enabled when using this and that is the
`unstable` signal. A test suite that is executed on developer breadboards can
have intermitten problems such as the probe being down, the breadboard failed
to power up, the test suite "locked up" the breadboard etc. See the
documentation further down for how to use `unstable`.

Note that you **probably** want to turn schemata off if the way that the tests
are executed do not pass on the environment variable `DEXTOOL_MUTID` to the
tests.

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
