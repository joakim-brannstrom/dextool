# Dextool Mutate

Dextool's plugin for mutation testing of C/C++ projects. It can help you design
new tests and evaluate the quality of existing tests by measuring their ability
to detect artificially injected faults.

Join the community at [discord](https://discord.gg/Gc27DyQ5yx).

## Overview

 * See [config options](README_config.md) for detailed explanations of the
   configuration options.
 * See [continues integration](README_ci.md) contains a guide for how to
   integrate dextool mutate.
 * See [parallel](README_parallel.md) for how to run multiple workers in parallel.
 * See [embedded systems](README_embedded.md) for configuration and guides for
   using dextool mutate for embedded systems.
 * See [mutation operators](doc/design/mutations.md) for the in depth details
   of the mutants that dextool generate.
 * See [apply mutation testing](README_tutorial.md) for how to apply mutation
   testing on a project.

Note: the build instructions is in the root `README.md` of this repo.

## Features

* 💉 Supports conventional mutation operators:
    [AOR, ROR, DCC, DCR, LCR, SDL, UOI](https://github.com/joakim-brannstrom/dextool/blob/master/plugin/mutate/doc/design/mutations.md).
* 📈 Provides multiple [report](#report) formats (Console, Compiler warnings,
  JSON, HTML).
* 💪 Detects "useless" test cases that do not kill any mutants.
* 💪 Detects "redundant" test cases that kill the same mutants.
* 💪 Detects "redundant" test cases that do not uniquely kill any mutants.
* 💪 Lists "near" test cases from which a new test can be derived to kill a
  surviving mutant of interest.
* 🔄 Supports [change-based mutation testing](README_ci.md#change-based) for
  fast feedback in a pull request workflow.
* 🐇 Can [continue](README_ci.md#incremental-mutation-test) from where a
  testing session was interrupted.
* 🐇 Allows multiple instances to be [run in parallel](README_parallel.md).
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

Mutation testing is a software testing technique and an active research area.
It was first proposed in 1971 by Richard Lipton. The technique can be described
as a process in which the "tests are tested" in order to determine the adequacy
of the test suite. Code coverage determine the adequacy of the test suite by
executed the system under test and measuring how much this execution covered of
the total program. Mutation testing determine the adequacy by injecting
syntactical faults (mutants) and executing the test suite. If the test suite
"fail" it is interpreted as the syntactical fault (mutant) being found and
killed by the test suite (good).

Mutation testing requires a test to verify the output in order to kill a
mutant. A test suite that kill a mutant thus *detected* the semantic change and
by killing the mutant reject the behavior change.

The algorithm for mutation testing is thus:

 * inject one mutant.
 * execute the test suite.
 * if the test suite **failed** record the mutant as **killed** otherwise
   **alive**.

The type of mutant that is injected follow a *schema* which in the literature
is called a "mutant operator". The mutation operators focus on different
semantical changes such as logical, control flow, data flow, *math*, boundary
etc.

The recommended operators to use try to affect the logic and data flow:

 * lcr/lcrb. Changes all `&&` and `||`.
 * sdl. Deletes block of code. Strongly affects the data flow such as
   assignments and calls.
 * dcr. Replaes logic with `true` and `false`. Strongly affects the control
   flow.
 * uoi. Deletes negation `!`.

Optional that are good candidates are:

 * rorp. Changes the relational operators such as `<` to its close relative
   `<=`. Strongly affects the boundaries how values are used and indexing.
 * aor. Mutates math operations such as `+`.

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
Figure: Over view of Dextool Mutate operational phases.

The mutation testing plugin, Dextool Mutate, functions in such a way that the
user provides a configuration-file where scripts, settings, and different paths
are specified. The picture above shows the flow for the plugin, where the test
part of mutation testing, is depicted in a more detailed manner. As shown in
the image, the plugin is divided into different parts (executable commandos) -
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
dextool mutate report --style html --section summary --section tc_stat --section tc_killed_no_mutants --section tc_unique --section score_history
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
