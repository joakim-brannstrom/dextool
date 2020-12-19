# Command Line Options

This document aims to improve usability for the *Mutate* plugin in Dextool by
explaining flags and options in more detail. The following sections are divided
into the current existing commands for *Mutate*.

The flags for the different commands will be listed in the following format:

```sh
--flag-long-version [-flag-short-version]
```
Description

```sh
input_example
```

**Note:** Several of the commands listed below can be set in the
configuration-file as well. It is recommended to generate an *.toml*-file and
set the corresponding fields in that file instead of having long chains of
commands to execute in the terminal (it is usually more simple that way,
reduces clutter in the terminal and increase usability for coming test
sessions). The information listed below can also be viewed by executing
*dextool mutate --help* in a terminal window, but with a shorter and less
detailed explanation.

## General

This options are general and can be used for all the commands in Mutate.

```sh
--config [-c]
```
Load configuration (default: .dextool_mutate.toml). Can be used if another
project contains a configuration-file which the users wants to reuse.


```sh
--db
```
Specify which sqlite3 database to use for the mutation testing (default:
dextool_mutate.sqlite3). This option could be used when several databases
exists for i.e. different versions of the code, or simply because the user have
chosen to create several databases for result.

```sh
--out
```
Path used as the root for mutation/reporting of files (default: .).

```sh
--help [-h]
```
Display the help information in terminal window (less detailed). By writing,
for example, *dextool mutate analyze --help*, the user will display the help
for the analyze command.

### Common

These are options that occur in multiple command groups.

```sh
--mutant
```
Mutants to operate on.
 - *all* : All mutants are generated.
 - *abs* : Absolute Value Insertion.
 - *aor* : Arithmetical Operator Replacement.
 - *dcc* : Decision/Condition Coverage.
 - *dcr* : Decision/Condition Requirement.
 - *lcr* : Logical Connector Replacement.
 - *lcrb* : Logical Connector Replacement (Bit-wise).
 - *ror* : Relational Operator Replacement.
 - *rorp* : Relational Operator Replacement (Pointer).
 - *sdl* : Statement Deletion.
 - *uoi* : Unary Operator Insertion.

```sh
--restrict
```
Restrict analysis to files in this directory tree (default: .). This option can
be used to make sure that mutations are not generated for specific files
outside a specific directory tree. This option together with a generated
compilation-database specified with *--compile-db* lets *Mutate* iterate over
every file in the project, and compares their paths to the *restricted area*.

```sh
--compile-db
```
Retrieve compilation parameters from a specific compilation-database. This can
be used if the projects contains specific compilation-databases for ex.
compilation targets or environments.

```sh
--diff-from-stdin
```
Reads a diff/patch in the git format (Unified Format) from stdin. It will
always, for all command groups it is available, affect the files and lines that
are tested/reported.

```sh
# only analyze and save mutants in the changed files
git diff|dextool mutate analyze --diff-from-stdin
# only test mutants on the changed lines
git diff|dextool mutate test --diff-from-stdin
# only report mutants on the changed lines
git diff|dextool mutate report --diff-from-stdin
```

```sh
--profile
```
The operations in dextool are not free especially the more complex reports.
This option print a table of what the tool internally spent time on.

## Admin

Admin-mode for the plugin. Is used to execute administrative commands and to
initialize/setup mutation testing for a project.


```sh
--init
```
Create an initial configuration to use in the current workspace. This command
is used when the mutation testing is setup for a specific project the first
time.

```sh
--dump-config
```
Dump the detailed configuration in the terminal. Could be used to create and
setup your own configuration-file.

```sh
--operation
```
Administrative operation to perform:
 - *none* : Performs no operation.
 - *resetMutant* : lets the user reset all mutants with the status/state
   specified with *--status* to the status specified with *--to-status*.
 - *removeMutant* : Remove all mutants of the specified kind (*--mutant*) from
   the database.
 - *removeTestCase* : Remove all test cases that match the supplied regex.
 - *markMutant*: Mark a mutant with a specific status and provide a rationale.
   Will both mark the mutant in mutationStatusTable and in a separate table.
 - removeMarkedMutant : remove the marking of a mutant.
 - resetTestCase : reset the mutants that the test case has killed to unknown (ignore `--to-status`)
 - compact : run a sqlite vacuum on the database with the goal of reducing the
   database size. This is automatically done after operations that normally
   result in a potentially significant reduction of the database size so most
   often this option is not needed.
 - stopTimeoutTest : changes the states in the database and internal worklists
 - such that the test phase will finish the timeout testing faster. This may be
   desired if there are many timeout mutants and it takes a long time to
   execute each of them.
 - resetMutantSubKind : same as resetMutant but only operates on the
   sub-mutation kinds which have a higher precision of which ones are affected.
 - clearWorklist : clear the worklist of mutants to test.

```sh
--test-case-regex
```
Regular expression to use when removing (*removeTestCase*) or resetting (*resetTestCase*) test cases.

```sh
--status
```
Change mutants with this status/state to the value specified by
*--to-status-flag*. The typical usage of this option is to reset the mutants
with *alive* status to *unknown* in order to conduct mutation testing again
after the test suite has been extended.
 - *unknown* : Mutants that is either untested or caused unknown errors when trying to execute compilation script.
 - *killed* : Mutants that were detected by the test suite (one or more tests failed).
 - *alive* : Mutants that were not detected by the test suite (all tests passed).
 - *killedByCompiler* : Invalid mutants generated that caused the compilation
   of the project to fail.
 - *timeout* : Mutants that timed out during test suite execution.

```sh
--to-status
```
Reset mutants to status/state (default: unknown). (see *--status*).
 - *unknown* : Mutants that is either untested or caused unknown errors when trying to execute compilation script.
 - *killed* : Mutants that were detected by the test suite (one or more tests failed).
 - *alive* : Mutants that were not detected by the test suite (all tests passed).
 - *killedByCompiler* : Invalid mutants generated that caused the compilation of the project to fail.
 - *timeout* : Mutants that timed out during test suite execution.

```sh
--id
```
Specify a specific mutant by Id.

```sh
--rationale
```
Provide a rationale for marking a mutant.

```sh
--mutant-sub-kind
```
The mutation operators are internally divided in 40+ sub categories. This
specify which of them to affect.

## Analyze

Analyze-mode for the plugin. Is used to find mutation points in the project by
traversing the AST for the eligible files. Will write results into a database
that will be used later for testing and generation of mutants.

```sh
--compile-db
```
Retrieve compilation parameters from a specific compilation-database. This can
be used if the projects contains specific compilation-databases for ex.
compilation targets or environments.

```sh
--in
```
Specific input file to parse. By default, all files in the compilation database will be analyzed.

```sh
--restrict
```
Restrict analysis to files in this directory tree (default: .). This option can
be used to make sure that mutations are not generated for specific files
outside a specific directory tree. This option together with a generated
compilation-database specified with *--compile-db* lets *Mutate* iterate over
every file in the project, and compares their paths to the *restricted area*.

## Generate

Generate-mode for the plugin.

```sh
--id
```
Mutate the source code as mutant ID

## Report

Report-mode for the plugin. Is used to generate a result-report at any given
moment (before, after or during mutation testing execution). Can also be used
to generate specific result that helps a user improve test cases among other.

Not all `--section` are supported by all report `--style`s. `plain` supports
all of them. The rest are implemented as needed and if it is feasible.

```sh
--level
```
Report level of the mutation data:
 - *summary* : Create a report that is a summary of the result.
 - *alive* : Create a report that only lists the alive mutants.
 - *all* : Create a report that contains all the mutants.

```sh
--logdir
```
Directory to write log files to (default: .).

```sh
--section
```
Sections to include in the report.
 - *alive* : Alive mutants.
 - *killed* : Killed Mutants.
 - *all_mut* : All mutants.
 - *summary* : A summary of the result.
 - *mut_stat* : The top N mutations *from* -> *to* that has survived (e.g. "-" -> "+").
 - *tc_killed* : The mutants that each test case killed.
 - *tc_stat* : Test case statistics based on the number of mutants that are killed.
 - *tc_map* : TODO
 - *tc_suggestion* : TODO
 - *tc_killed_no_mutants* : Provide a list of tests that killed no mutant.
 - *tc_full_overlap* : Provide a list of tests that killed the exact same
   mutants (candidates for redundant test cases).
 - *tc_full_overlap_with_mutation_id* : Provide a list of tests that killed the
 - exact same mutants (candidates for redundant test cases), but include the id
   of the mutants.
 - *tc_groups* : Test case groups.
 - *tc_min_set* : Provide the minimal set of test cases needed in order to
   achieve the mutation score.
 - *tc_similarity* : Provide a list of tests and to what degree they are
   similar in terms of mutants the kill.
 - *tc_groups_similarity* : Compare the similarity between test groups. This is
   a "group" view compared to *tc_similarity*.
 - *treemap* : Generate a treemap for the project (is currently unstable for
   large projects and files that have very long filenames).
 - *mut_recommend_kill* :
 - *diff* : add a page that shows the diff as git would do it together with the
   mutants on the changed lines.
 - *tc_unique* : for each test case report the mutants that the test case is the
   only one to kill.
 * *marked_mutants* : a table with the manually marked mutants.
 * *score_history* : print the recorded mutation score, one for each day.

```sh
--section-tc_stat-num
```
Number of test cases to report that killed a mutant (will affect the drop-down
in the html-report).

```sh
--section-tc_stat-sort
```
Sort order when reporting test case kill stat.
 - *top* : Sort from top to bottom.
 - *bottom* : Sort from bottom to top.

```sh
--style
```
Kind of report to generate. Lets a user specify if the format of the report.
This could be used if the report is to be pased into an excel-document, or
viewed graphically in the browser etc.
 - *plain* : Generates a plain text summary of the result and prints it in the
   terminal window.
 - *compiler* : Same as *plain* but in compiler-format.
 - *json* : Same as *plain* but in .json-format.
 - *html* : Generates an html-report with all the chosen sections. Is the main
   way of inspect mutation testing result since many of the other commands for
   *Report* is linked to this kind of report. Can be viewed in a browser by
   opening the generated *index.html*-file directly.

## Test

Test-mode for the plugin. Injects a mutant into the source code, compiles the
project to see if the mutants was valid and then executes the test suite in
order to analyze whether or not the test suite detected the mutant. Will also
check if the mutant caused an infinity-loop, or simply took longer time than
usual, by utilizing the timeout-implementation.

```sh
--build-cmd
```
Program/script used to build the application. Will be called to compile both
the original program (sanity check) and to compile the program each time a
mutant is injected.

```sh
--dry-run
```
Do not write mutants to the filesystem. This is intended to be used by dextools
internal tests to fejk mutation testing runs.

```sh
--order
```
Determine in what order mutations are chosen.
 - *random* : Execute the mutations in a random order.
 - *consecutive* : Execute the mutations consecutive by the mutant id.

```sh
--test-cmd
```
Program/script used to run the test suite. Will be called upon by *Mutate* in
order to test the application (both for sanity-checks and when a mutant has
been injected in the code).

```sh
--test-case-analyze-builtin
```
Builtin analyzer of output from testing frameworks to find failing test cases.
Can be used in order to specify a framework used for testing and letting
Dextool analyze the output from test-results according to that framework.
 - *gtest* : Analyzes the test case result according to the Googletest-format.
 - *ctest* : Analyzes the test case result according to the Ctest-format.
 - *makefile* : Analyzes the test case result according to the makefile-format.

```sh
--test-case-analyze-cmd
```
Program/script used to analyze the test execution result. Will be called upon
by *Mutate* in order to analyze the tests for the application (both for
sanity-checks and when a mutant has been injected in the code).

```sh
--test-timeout
```
Timeout to use for the test suite (msecs). This option lets the user manually
set the timeout-limit. It is recommended to let *Mutate* use the builtin
algorithm for this since the time it takes to execute test suites varies.

```sh
--check-schemata
```
An injected schemata should, when no mutant is activated, not affect the result
of the test suite. This option execute the test cases after the schemata has
been injected to see that all tests still pass. If it fails the specific
schemata is discarded. This is a good sanity check to have active because
schematan are still being developed and have been observed to sometimes
negatively affect the test suite.

```sh
--log-schemata
```
Save the schematan, as they are used, to a file by their ID-number for later
analysis. This option is mostly intended for developers of dextool.

```sh
--max-alive <nr>
```
Run the mutation testing until `nr` alive mutants have been found. Intended to
be used when integrating mutation testing with pull requests to have an early
halting condition.

```sh
--only-schemata
```
Only use schematan for the test phase. Depending on the operators this mean
that between 50-100% of the mutants can be tested pretty fast.

```sh
--pull-request-seed <nr>
```
The order the mutants are tested when running mutation testing on a diff.
Normally the year+week is used as a seed in order to keep the mutants that are
tested stabel over multiple updates of a pull request. This option can be used
to force a specific seed to be used.

```sh
--use-schemata
```
If schematan should be used. Dextool will start by trying to use all schematan
that have mutants that are in the worklist. When all schematan are consumed
dextool will fall back to the slower source code mutating.

```sh
--use-early-stop
```
If dextool should stop executing the test suite as soon as it finds one failing
test case. The *precicion* of the reports containing sections about test cases
will be lower because dextool hasn't gathered complete information. But this is
usually not a problem and far offset by the significant reduction in execution
time that this option can achieve.

```sh
--max-runtime
```
To run mutation testing to completion can take a long time. This option
configures that dextool should terminate testing after the specified time.
This allows dextool to run for e.g. 3h, stop, generate a report and then
restart. It thus gives continues feedback of the progress.

```sh
dextool mutate test --max-runtime "1 hours 30 minutes 10 msecs"
```

```sh
--load-behavior
```
Running mutation testing is taxing on the IT infrastructure. This option
configures how to behave when the load goes above the threshold.
 * nothing : ignore, do nothing. The default behavior.
 * slowdown : stop testing when the load goes above the threshold.
 * halt : stop testing.

```sh
--load-threshold
```
The 15 minute loadavg threshold to control when the `--load-behavior` is
triggered. By default it is set to the number of virtual cores on the computer.

# Configuration File

The template that is generated by
```sh
dextool mutate admin --init
```

try to be self explaining. This section is thus focused on explaining the
different categories (`[....]`).

```toml
[workarea]
```
Configuration of the directories that dextool is allowed to change files in.

`root`: Defines the root directory that all phases of mutation testing will use.
 * the analyze phase will only store mutants that reside in the root or
   sub-directories.
 * the test phase will only mutate files that is inside the root.
 * the report will make all paths relative to the root.

`restrict`: A project may contain want to further restrict what
directories/files should be mutated inside the root. It could for example be so
that the src and test is inside the same root. To discover all available
mutants, C++ templates, the analyser must analyze test cases because templates
are instantiated there. But it is obviously so that the tests should not be
mutated. By configuring this option to `restrict=["src"]` it means that only
the mutants inside `{root}/src` are saved in the database.

```toml
[generic]
```
Generic options that affect all phases that. The most important to configure
here is the mutation operators to use (`mutants`). It affects what mutants are
saved in the database, which ones are mutated and reported.

```toml
[database]
```
Database options.

```toml
[compiler]
```
Options for the compiler such as extra flags to add or if a specific compiler
should be used instead of the one found in the `compile_commands.json` file.

`use_compiler_system_includes`: Extract all system includes from this compiler
instead of the one that is used in `compile_commands.json`. This is important
for e.g. cross compilers or older versions of GCC. A cross-compiler may point
to a C++ stdlib that isn't compatible with clang which would lead to a total
analysis failure. By *fooling* dextool to instead derived the system includes
from another compiler it is still possible to complete the analysis phase.

```toml
[compile_commands]
```
Configuration of which `compile_commands.json` to use and how it should be
filtered.

`filter`: Use to remove flags that aren't compatible with clang such as `-W`
that only exist in GCC.

`skip_compiler_args`: Sometimes the first argument isn't the compiler. Dextool
need to know where the compiler "start" in the argument list because the system
includes are extracted from the compiler.

```toml
[mutant_test]
```
Configuration of the test phase. This contains the most options because it is
also the one that has to be flexible.

`build_cmd`: Program/script used to build the application. Will be called to
compile both the original program (sanity check) and to compile the program
each time a mutant is injected.

`test_cmd_dir`: The directory is analyzed for executables. All executables that
are found then used as test case binaries. This is a convenient option to use
when they are all in a directory easily accessible.

`test_cmd_dir_flag`: The flags here are used when executing binaries found via
`test_cmd_dir`. It is a convenient way of inactivating test cases in e.g.
Googletest.

`test_cmd`: If `test_cmd_dir` isn't suitable to use then this allows a manual
specification of the test binaries to execute together with, for the complex
cases, also specifying the flags to use per command.

`test_cmd_timeout`: Timeout of the test suite. This should normally **not** be
used. The default for dextool is to use a dynamic timeout that is derived by
measuring the test suites execution time together with a timeout-re-test
algorithm that re-execute timeouts together with increasing until no visible
change is detected. By setting this option dextool will **not** derive the
execution and will **not** use the timeout-re-test algorithm.

`build_cmd_timeout`: Configures a timeout for the build command. Use if the
build system can have intermittent lockups. The default is one hour.

`analyze_cmd`: Configures dextool to call this command to analyze the output of
the test suite to derived which test cases that exist, which ones that killed a
mutant and stability. The intended use case of this option is embedded
developers that use a minimal, custom test framework.

`analyze_using_builtin`: Use one or more of the builtin test framework
analyzers.

`detected_new_test_case`: A programs test suite that evolve over time may add
new test cases. This control how dextool will behave when it finds a new test
case. Either just ignore it or re-test all mutants that has survived (alive) to
see if the new test cases kill any of those that previously survived.

`detected_dropped_test_case`: Configures what dextool should do with the stored
information about a test case which it detects has been removed. Either just
leave it as it is or remove it. If the test case is removed all mutants that
the test case uniquelly killed will be reset to `unknown` statues which will
trigger them to be re-tested.

`oldest_mutants`: The tool is unaware of the tests and if they have changed.
This is a configuration that tell the tool to re-test old mutants to see if
anything has changed in the test suite. The re-test, if activated, of old
mutants will only be done if there is nothing else to be done.

`parallel_test`: How many test binaries to run in parallel.
