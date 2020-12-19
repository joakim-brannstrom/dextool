# Continues Integration

Dextool is built to be easily used incrementally and on e.g. a Jenkins server.
All shared states are saved in a sqlite3 database.

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
