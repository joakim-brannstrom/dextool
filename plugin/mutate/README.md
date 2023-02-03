# Dextool Mutate

Dextool Mutate is a mutation testing tool for C/C++. It can help you
design new tests and evaluate the quality of existing tests by measuring their
ability to detect artificially injected faults.

Join the community at [discord](https://discord.gg/Gc27DyQ5yx).

## Overview

 * See [installation](https://github.com/joakim-brannstrom/dextool/blob/master/README.md#Installation)
   for how to build and install dextool.
 * See [config options](README_config.md) for detailed explanations of the
   configuration options.
 * See [continues integration](README_ci.md) for how to integrate dextool mutate.
 * See [parallel](README_parallel.md) for how to run multiple workers in parallel.
 * See [embedded systems](README_embedded.md) for how to use the tool in an embedded systems environment.
 * See [mutation operators](doc/design/mutations.md) for in depth details of the generated mutants.
 * See [apply mutation testing](README_tutorial.md) for how to apply mutation
   testing on a project.
 * See [fmt tutorial](README_tutorial_fmt.md) for a practical example of
   running mutation testing.
 * See [roadmap](README_roadmap.md) for where dextool mutate is headed in the
   future.

## Features

* 💉 Supports conventional mutation operators:
    [AOR, ROR, DCC, DCR, LCR, SDL, UOI](doc/design/mutations.md).
* 💉 Supports extreme mutation where entire functions/methods are removed.
* 📈 Provides multiple [report](#report) formats (Console, Compiler warnings,
  JSON, HTML).
* 💪 Detects "useless" test cases that do not kill any mutants.
* 💪 Detects "redundant" test cases that kill the same mutants.
* 💪 Detects "redundant" test cases that do not uniquely kill any mutants.
* 💪 Lists "near" test cases that can be helpful when [killing a mutant](#kill).
* 🔄 Supports [change-based mutation testing](README_ci.md#change-based) for
  fast feedback in a pull request workflow.
* 🐇 Can [continue](README_ci.md#incremental-mutation-test) from where a
  testing session or analysis was interrupted.
* 🐇 Allows multiple instances to be [run in parallel](README_parallel.md).
* 🐇 Can reuse previous results when the SUT changes by only testing the change.
* 🐇 Can automatically [rerun the mutations that previously survived](#re-test-alive)
  when new tests are added.
* 🐇 Does automatic handling of infinite loops (timeout).
* 🐇 Uses coverage information to only test mutants in functions/methods
  covered by the tests.
* 🐇 Uses [mutant schemata](doc/design/notes/schemata.md) to compile and link
  once per SUT, rather than once per mutant.
* 🔨 Works with all C/C++ versions.
* 🔨 Works with C++ templates.
* 🔨 Integrates without modifications to the projects build system.
* 🔨 Lets a user modify it by using a SQLite database as intermediary storage.
* 🔨 Lets a user mark a mutant as [dont care](#mark-mutant).

# Mutation Testing

Mutation testing is a software testing technique in which small, deliberate
changes are made to the source code, and the system is then tested to see if it
can detect the changes, also known as mutations. This helps to evaluate the
quality of the test suite and determine if it provides adequate coverage and is
able to detect faults in the code. The idea is that if the tests can detect the
changes, then they are strong and likely to detect actual faults in the code.

To use mutation testing, you need to follow these general steps:

 * Create test cases: You need to have a set of automated test cases that cover
   the codebase. The goal is to ensure that the mutations introduced in the
   code are detected by the tests.
 * Run dextool mutate: You run the mutation testing tool on your codebase and
   let it make mutations to the source code. The tool will then run the test
   suite to see if the tests can detect the mutations.
 * Analyze the results: The tool will provide a report on the number of mutants
   that were killed (detected by the tests) and the number of alive (not
   detected by the tests). You can then analyze the results to determine which
   parts of the code need more testing and which test cases need to be updated.
 * Improve the tests: Based on the results of the mutation testing, you can
   improve the test suite by adding more test cases, updating existing ones to
   ensure that they detect all mutations or refactor the codebase.

The algorithm for mutation testing is thus:

 * Inject one mutant.
 * Execute the test suite.
 * If the test suite **failed** record the mutant as **killed** otherwise
   **alive**.

The mutants are generated following a schema, which in the literature is called
a "mutation operator". The mutation operators focus on different semantical
changes such as logical, control flow, data flow, *math*, boundary etc.

The recommended operators to use try to affect the logic and data flow:

 * lcr/lcrb. Changes all `&&` and `||`.
 * sdl. Deletes block of code. Strongly affects the data flow such as
   assignments and calls.
 * dcr. Replaes logic with `true` and `false`. Strongly affects the control
   flow.
 * uoi. Delete negation `!`.

Optional that are good candidates are:

 * aor. Mutates math operations such as `+`.
 * aors. Same as aor but instead of generating 4 mutants it only generates the
   counter mutation e.g. + to -. It thus is 1/4 of the mutants
 * rorp. Changes the relational operators such as `<` to its close relative
   `<=`. Strongly affects the boundaries how values are used and indexing.
 * cr. Replace constants with zero.

See [mutaton operators](README_mutation_operators.md) for a detailed explanation.

```
/---------------------------\    /-----------------------------------------------------\
| Setup config files and    |    | /----------\ /---------\  /------------\            |
| create executable scripts |--->| | build.sh | | test.sh |  | analyze.sh |            |
\---------------------------/    | \----------/ \---------/  \------------/            |
       ||                        \----^------------^-------------^-Executable scripts--/
       \/                             |            |             |
/-------------------------------------------------------------------------------------------\
| Dextool Mutate                      |            |             |                          |
|                                     |            |             |                          |
| /---------\                         |            |             |                          |
| | Analyze |    /-------------------------------------------------------------------\      |
| \---------/    | Loop for every mutant           |             |                   |      |
|     ||         |                    |            |             |                   |      |
|     \/     /---------------\   /---------\   /---------\   /---------\   /-------------\  |
| /------\   | Insert mutant |   | Compile |   | Execute |   | Analyze |   | Mark mutant |  |
| | Test |-->| in code       |-->| Project |-->| tests   |-->| test    |-->| in DB       |  |
| \------/   \---------------/   \---------/   \---------/   | result  |   \-------------/  |
|     ||         | ^                 ^             ^         \---------/         ||  |      |
|     ||         \-|-----------------|-------------|------------^----------------||--/      |
|     ||           |                 |             |            |                \/         |
|     \/           \--------------------------------------------------------------------------->/--------------\
| /----------                                                                               |   | Database for |
| | Report |                                                                                |   | mutants.     |
| \--------/                                                                                -   \--------------/
|                                                                                           |
\-------------------------------------------------------------------------------------------/
```
Figure: Overview of Dextool Mutate's operational phases.

When using Dextool Mutate, the user starts by providing a configuration-file
where scripts, settings, and paths are specified. The picture above shows that
the flow of the tool is divided into different parts (executable commandos) -
analyze, test and report.

## Test Phase Execution Flow

The test phase use the configuration files content in the following way when
executing:

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
5. Save the result in the database. The result consist of the status
   (killed/alive), which test cases that failed (killed the mutant) and
   execution time.

## Report <a name="report"></a>

The report phase contains a multitude of simple reporters together with more
complex analysis of the test cases. A report is composted of `section`s,  see
[report](README_config.md#report) for details.

A basic report with a file list, statistics and some simple test case
analysises is:

```sh
dextool mutate report --style html --section summary --section tc_suggestion --section tc_killed_no_mutants --section tc_unique --section tc_similarity
```

## Killing a Mutant <a name="kill"></a> 🦁

The HTML report will for every killed mutant list the test cases that killed it
when the mutant is expanded.

When investigating a surviving mutant; some of the killer test cases in the
neighbourhood might be good candidates for improvement or deriving a new test.

Next to the killer test case is a number that tells how many mutants it killed.

* A low number suggests that the test covers a corner case.
* A high number suggests that the test covers many aspects.

If you add the report section `tc_suggestion` you will for each test case get a
`Suggestion` column.  For every mutant that a test case kill a list of mutants
at the same source code location that are alive are listed.

## Mark a Mutant as Dont Care <a name="mark-mutant"></a> 🤷

There are two ways of marking a mutant to the tool as "don't care". These are
either via a source code annotation or by attaching a forced mutation status to
a mutation ID.

There are three flavors of annotations (comments beginning with `//`)
supported.

 * `NOMUT`. All mutants on the line are marked.
 * `NOMUTBEGIN` / `NOMUTEND`. All mutants in the block are marked. 
 * `NOMUTNEXT`. All mutants on the next line are marked.

 All variants support additional metadata that help to organize and explain why
 the mutants are ignored.
 * `(tag)`. The tag is used to group the annotations together in the HTML report.
    A good group could be "trace log".
 * `(tag) a comment`. The comment is added to the HTML report as a separate column.

 Example:
 ```c++
int x = 42; // NOMUT (log trace) will never be tested
// NOMUTBEGIN (log trace) will never be tested
int y = 43; 
// NOMUTEND
// NOMUTNEXT (log trace) will never be tested
int z = 43; 
 ```

All mutants that are marked is subtracted from the total when calculating the
mutation score. Additional fields in the statistics are added which highlight
how many of the total that are annotated as `NOMUT`.

In the HTML report the `tag` is used to group mutants to make it easier to
distinguish them from each other and help in understanding why they are
ignored. Such as a call to a logging library is probably not worth adding test
cases for.

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
