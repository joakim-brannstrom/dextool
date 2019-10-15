# Options and flags
partof: DOC-plugin_mutate

This document aims to improve usability for the *Mutate* plugin in Dextool by explaining flags and options in more detail. The following sections are divided into the current existing commands for *Mutate*.

The flags for the different commands will be listed in the following format:

- *--flag-long-version [-flag-short-version] : Description*
    - *input_example*

**Note:** Several of the commands listed below can be set in the configuration-file as well. It is recommended to generate an *.toml*-file and set the corresponding fields in that file instead of having long chains of commands to execute in the terminal (it is usually more simple that way, reduces clutter in the terminal and increase usability for coming test sessions). The information listed below can also be viewed by executing *dextool mutate --help* in a terminal window, but with a shorter and less detailed explanation.

## General
*This options are general and can be used for all the commands in Mutate.*


- --config [-c] : Load configuration (default: .dextool_mutate.toml). Can be used if another project contains a configuration-file which the users wants to reuse.


- --db : Specify which sqlite3 database to use for the mutation testing (default: dextool_mutate.sqlite3). This option could be used when several databases exists for i.e. different versions of the code, or simply because the user have chosen to create several databases for result.


- --out : Path used as the root for mutation/reporting of files (default: .).


- --help [-h] : Display the help information in terminal window (less detailed). By writing, for example, *dextool mutate analyze --help*, the user will display the help for the analyze command.

## Admin
*Admin-mode for the plugin. Is used to execute administrative commands and to initialize/setup mutation testing for a project.*


- --dump-config : Dump the detailed configuration in the terminal. Could be used to create and setup your own configuration-file.


- --init : Create an initial configuration to use in the current workspace. This command is used when the mutation testing is setup for a specific project the first time.


- --mutant : Mutants to operate on.
    - *any* : Any (all) mutants are generated.
    - *ror* : Relational Operator Replacement.
    - *rorp* : Relational Operator Replacement (Pointer).
    - *lcr* : Logical Connector Replacement.
    - *lcrb* : Logical Connector Replacement (Bit-wise).
    - *aor* : Arithmetical Operator Replacement.
    - *uoi* : Unary Operator Insertion.
    - *abs* : Absolute Value Insertion.
    - *sdl* : Statement Deletion.
    - *cor* : Conditional Operator Replacement.
    - *dcc* : Decision/Condition Coverage.
    - *dcr* : Decision/Condition Requirement.


- --operation : Administrative operation to perform
    -   *none* : Performs no operation.
    -   *resetMutant* : lets the user reset all mutants with the status/state specified with *--status* to the status specified with *--to-status*.
    -   *removeMutant* : Remove all mutants of the specified kind (*--mutant*) from the database.
    -   *removeTestCase* : Remove all test cases that match the supplied regex.


- --test-case-regex : Regular expression to use when removing test cases.


- --status : Change mutants with this status/state to the value specified by *--to-status-flag*. The typical usage of this option is to reset the mutants with *alive* status to *unknown* in order to conduct mutation testing again after the test suite has been extended.
    - *unknown* : Mutants that is either untested or caused unknown errors when trying to execute compilation script.
    - *killed* : Mutants that were detected by the test suite (one or more tests failed).
    - *alive* : Mutants that were not detected by the test suite (all tests passed).
    - *killedByCompiler* : Invalid mutants generated that caused the compilation of the project to fail.
    - *timeout* : Mutants that timed out during test suite execution.


- --to-status : Reset mutants to status/state (default: unknown). (see *--status*).
    - *unknown* : Mutants that is either untested or caused unknown errors when trying to execute compilation script.
    - *killed* : Mutants that were detected by the test suite (one or more tests failed).
    - *alive* : Mutants that were not detected by the test suite (all tests passed).
    - *killedByCompiler* : Invalid mutants generated that caused the compilation of the project to fail.
    - *timeout* : Mutants that timed out during test suite execution.

## Analyze
*Analyze-mode for the plugin. Is used to find mutation points in the project by traversing the AST for the eligible files. Will write results into a database that will be used later for testing and generation of mutants.*


- --compile-db : Retrieve compilation parameters from a specific compilation-database. This can be used if the projects contains specific compilation-databases for ex. compilation targets or environments.


- --in : Specific input file to parse. By default, all files in the compilation database will be analyzed.


- --restrict : Restrict analysis to files in this directory tree (default: .). This option can be used to make sure that mutations are not generated for specific files outside a specific directory tree. This option together with a generated compilation-database specified with *--compile-db* lets *Mutate* iterate over every file in the project, and compares their paths to the *restricted area*.


## Generate
*Generate-mode for the plugin.*


- --restrict : Restrict analysis to files in this directory tree (default: .). This option can be used to make sure that mutations are not generated for specific files outside a specific directory tree. This option together with a generated compilation-database specified with *--compile-db* lets *Mutate* iterate over every file in the project, and compares their paths to the *restricted area*.


- --id : Mutate the source code as mutant ID


## Report
*Report-mode for the plugin. Is used to generate a result-report at any given moment (before, after or during mutation testing execution). Can also be used to generate specific result that helps a user improve test cases among other.*


- --compile-db : Retrieve compilation parameters from a specific compilation-database. This can be used if the projects contains specific compilation-databases for ex. compilation targets or environments.


- --diff-from-stdin : Report alive mutants in the areas indicated as changed in the diff.


- --level : Report level of the mutation data.
    - *summary* : Create a report that is a summary of the result.
    - *alive* : Create a report that only lists the alive mutants.
    - *all* : Create a report that contains all the mutants.


- --logdir : Directory to write log files to (default: .).


- --mutant : Kind of mutation to report.
    - *any* : Any (all) mutants are generated.
    - *ror* : Relational Operator Replacement.
    - *rorp* : Relational Operator Replacement (Pointer).
    - *lcr* : Logical Connector Replacement.
    - *lcrb* : Logical Connector Replacement (Bit-wise).
    - *aor* : Arithmetical Operator Replacement.
    - *uoi* : Unary Operator Insertion.
    - *abs* : Absolute Value Insertion.
    - *sdl* : Statement Deletion.
    - *cor* : Conditional Operator Replacement.
    - *dcc* : Decision/Condition Coverage.
    - *dcr* : Decision/Condition Requirement.


- --restrict : Restrict analysis to files in this directory tree (default: .). This option can be used to make sure that mutations are not generated for specific files outside a specific directory tree. This option together with a generated compilation-database specified with *--compile-db* lets *Mutate* iterate over every file in the project, and compares their paths to the *restricted area*.


- --section : Sections to include in the report.
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
    - *tc_full_overlap* : Provide a list of tests that killed the exact same mutants (candidates for redundant test cases).
    - *tc_full_overlap_with_mutation_id* : Provide a list of tests that killed the exact same mutants (candidates for redundant test cases), but include the id of the mutants.
    - *tc_groups* : Test case groups.
    - *tc_min_set* : Provide the minimal set of test cases needed in order to achieve the mutation score.
    - *tc_similarity* : Provide a list of tests and to what degree they are similar in terms of mutants the kill.
    - *tc_groups_similarity* : Compare the similarity between test groups. This is a "group" view compared to *tc_similarity*.
    - *treemap* : Generate a treemap for the project (is currently unstable for large projects and files that have very long filenames).


- --section-tc_stat-num : Number of test cases to report that killed a mutant (will affect the drop-down in the html-report).


- --section-tc_stat-sort : Sort order when reporting test case kill stat.
    - *top* : Sort from top to bottom.
    - *bottom* : Sort from bottom to top.


- --style : Kind of report to generate. Lets a user specify if the format of the report. This could be used if the report is to be pased into an excel-document, or viewed graphically in the browser etc.
    - *plain* : Generates a plain text summary of the result and prints it in the terminal window.
    - *markdown* : Same as *plain* but in .md-format.
    - *compiler* : Same as *plain* but in compiler-format.
    - *json* : Same as *plain* but in .json-format.
    - *csv* : Same as *plain* but in .csv-format.
    - *html* : Generates an html-report with all the chosen sections. Is the main way of inspect mutation testing result since many of the other commands for *Report* is linked to this kind of report. Can be viewed in a browser by opening the generated *index.html*-file directly.


## Test
*Test-mode for the plugin. Injects a mutant into the source code, compiles the project to see if the mutants was valid and then executes the test suite in order to analyze whether or not the test suite detected the mutant. Will also check if the mutant caused an infinity-loop, or simply took longer time than usual, by utilizing the timeout-implementation.*


- --build-cmd : Program/script used to build the application. Will be called upon by *Mutate* in order to compile the application (both for sanity-checks and when a mutant has been injected in the code).


- --dry-run : Do not write data to the filesystem.


- --mutant : Kind of mutation to test.
    - *any* : Any (all) mutants are generated.
    - *ror* : Relational Operator Replacement.
    - *rorp* : Relational Operator Replacement (Pointer).
    - *lcr* : Logical Connector Replacement.
    - *lcrb* : Logical Connector Replacement (Bit-wise).
    - *aor* : Arithmetical Operator Replacement.
    - *uoi* : Unary Operator Insertion.
    - *abs* : Absolute Value Insertion.
    - *sdl* : Statement Deletion.
    - *cor* : Conditional Operator Replacement.
    - *dcc* : Decision/Condition Coverage.
    - *dcr* : Decision/Condition Requirement.


- --order : Determine in what order mutations are chosen.
    - *random* : Execute the mutations in a random order.
    - *consecutive* : Execute the mutations consecutive by the mutant id.


- --restrict : Restrict analysis to files in this directory tree (default: .). This option can be used to make sure that mutations are not generated for specific files outside a specific directory tree. This option together with a generated compilation-database specified with *--compile-db* lets *Mutate* iterate over every file in the project, and compares their paths to the *restricted area*.


- --test-cmd : Program/script used to run the test suite. Will be called upon by *Mutate* in order to test the application (both for sanity-checks and when a mutant has been injected in the code).


- --test-case-analyze-builtin : Builtin analyzer of output from testing frameworks to find failing test cases. Can be used in order to specify a framework used for testing and letting Dextool analyze the output from test-results according to that framework.
    -   *gtest* : Analyzes the test case result according to the Googletest-format.
    -   *ctest* : Analyzes the test case result according to the Ctest-format.
    -   *makefile* : Analyzes the test case result according to the makefile-format.


- --test-case-analyze-cmd : Program/script used to analyze the test execution result. Will be called upon by *Mutate* in order to analyze the tests for the application (both for sanity-checks and when a mutant has been injected in the code).


- --test-timeout : Timeout to use for the test suite (msecs). This option lets the user manually set the timeout-limit. It is recommended to let *Mutate* use the builtin algorithm for this since the time it takes to execute test suites varies.
