# Continues Integration

Dextool is built to be easily used incrementally and on e.g. a Jenkins server.
All shared states are saved in a sqlite3 database.

## Incremental Mutation Testing <a name="incremental-mutation-test"></a>

All the states of running dextool mutate is saved in a database. This is the
fundamental building block that allows the tool to resume and reuse results
from previous executions.

The analyze phase will only save files that have changed and remove those that
it detects has been removed. A file that is renamed but whose content is not
changed will have all the mutation results moved to the new filename.

The test phase work on the, one at a time, mutants until all have a status that
isn't `unknown`. The test phase can detect when tests are added and removed
which affects the work it has to do. Removed test cases will change the status
of the mutants it uniquely killed to `unknown` while a new test case will
re-test all `alive` mutants to see if the new test case kill any of those that
previously survived.

The test phase can be interrupted and resumed at the users leisure without
loosing any of the results.

These features together means that even though the total runtime of fully
running mutation testing on a program may be weeks (one worker) any of the
results that it gathers are saved. If the program only slightly change over
time then the mutation testing will finish and be pretty snappy in the future.

### Re-test Alive Mutants <a name="re-test-alive"></a>

Lets say that we want to re-test the mutants that survived because new tests
have been added to the test suite. To speed up the mutation testing run we
don't want to test all mutants but just those that are currently marked as
alive.

This is achieved by changing the configuration file from `doNothing` to
`resetAlive`:
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
re-execute the mutants. Balance the percentage such that all mutants have been
re-tested in a reasonable amount of time.
```toml
oldest_mutants_percentage = 1.0
```

## Change Based Testing for Pull Request Integration <a name="change-based"></a>

It is important to give fast feedback on a pull request and herein lies the
problem for mutation testing; it isn't fast. But a pull request usually only
touch a small part of a code base, a small diff. Change based testing mean that
only those mutants on the changed lines are tested.

The recommended way of integrating this support is via git diff as follows:

Analyze only the changed files.
```sh
git diff | dextool mutate analyze --diff-from-stdin
```

Run the mutation testing on only those lines that changed:
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

## Jenkins

The guide herein is written for Jenkins but should work for any CI-server
setup.

A typical team wants a *total* status of the project based on the master branch
and have a fast feedback on the pull requests.

For the master branch it is recommended to run in batches of 3-9 hours
repeatably. This produces a continues update of the report and any changes to
the master is incorporated in the next report. To do this on Jenkins configure
the database as an *artifact* that is retrieved upon start and saved when
finished. Then the script for jenkins would basically be:

```sh
dextool mutate analyze --fast-db-store
dextool mutate test
dextool mutate report --style html --section summary --section tc_stat --section tc_killed_no_mutants --section tc_unique --section trend
```

The pull request job should **not** use the same database as the job that is
testing the master branch. This is because it takes a while to remove
unnecessary files. By instead always starting from scratch and only saving the
mutants that exists in the diff *correct* mutants are tested and reported. The
setup in jenkins would then look like:

```sh
git diff master|dextool mutate analyze --diff-from-stdin --fast-db-store
git diff master|dextool mutate test --diff-from-stdin
git diff master|dextool mutate report --style html --section summary --section diff
git diff master|dextool mutate report --style json --section summary
```
