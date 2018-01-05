# REQ-plugin_mutate-report
partof: REQ-plugin_mutate
###

The plugin shall produce a report:
 * that is *easy* to integrate in other tools.
 * that is *easy to read* by a human.

The plugin shall use the *human readable report* as the default report.

**Rationale**: This is based on the assumption that it is important to use defaults for the standalone scenario that make it easy for a human to interpret the results.

## Human Readable Report Content

The report shall at least contain information regarding the mutants as absolute numbers and the mutation score.

## Why Tool Integration?

The reporting to the user is part of the *user interface* thus it should be as good as possible.
The easier a tool is to use the higher is the likelihood that it will be used.

By making it easy to integrate in other tools it will allow the user to use mutation testing in a *live* manner.
Imagine the scenario if the live mutants are integrated in the IDE. The user can then make changes to the code, rerun the mutation testing and see the changes to the live mutations in the IDE. No context switching needed. Mutation testing is a click on a button.

Another positive effect is that the time to inspect live mutants are reduced compared to reading an external report.

## Why Human Readable Report

The intention is to generate a report such that it is easy to publish in other content systems.

## TODO

 * In the summary print a list of the mutations in the order of most -> least alive. Include the number.
 * Develop a statistical model for how potentially how many bugs there are left in the program that has not been discovered by tests.
 * Should the checksum be used when reporting mutations?
   It is probably a bad idea to "stop" reporting because the source code is not always accessable.
   But the user should be informed that the content is different.

# SPC-plugin_mutate_report_for_human
partof: REQ-plugin_mutate-report
###

The plugin shall produce a report in markdown format when commanded via the *CLI*.

**Rationale**: The user is interested in when the mutation is finished because it can take a long time to go through all mutations. All the data to do a simple *mean* approximation is available.

## Why?

Markdown is chosen because there exist many tools to convert it to other formats.
It is also easy for a human to read in the raw form thus it can be used as the default *console* report.

### Git Diff like Report

The user may want the output to be like `git diff`. But keep in mind that this is an *information leak* of the source code which may prohibit its usage when publishing to content systems so should be controllable by the user.

Decision: Not needed. The tool integration can be used for this.

# SPC-plugin_mutate_report_for_human-cli
partof: SPC-plugin_mutate_report_for_human
###

The command line argument *--report-level* shall control the *report level* of the human readable report.

The default *report level* shall be *summary*.

The plugin shall support the *report levels* {summary, alive, full}.

## Summary

The report shall contain a summary of the mutation testing.

The summary shall contain the following information:
 * number of untested mutants
 * number of alive/kiled/timeout mutants
 * the sum of the mutants (alive+killed+timeout)
 * the mutation score
 * the time spent on testing alive/killed/timeout mutants in a human readable format (days/hours/minutes/seconds...)
 * the total time spent on mutation testing

The plugin shall calculate a prediction as a date and absolute time for when the current running mutation is done when producing a report and there are any mutants left to test.

## Alive

The report shall contain the location of alive mutations.

A location for a mutant shall containg the following information:
 * the mutation ID
 * the status of the mutant (alive, unknown etc)
 * the kind of mutant (ror negation etc)
 * the file location
    * the path to the file
    * the line and column

The summary shall be the last section in the report.
**Note**: See ## Summary for the specification of the content
**Rationale**: This requirement is based on the assumption that the user is first interested in reading the summary of the mutation testing. By printing the summary last the user do not have to scroll in the console. This is though inverted if the user renders the markdown report as a webpage. Then the user probably want the summary at the top.

## Full

The report shall contain the location of all mutations.
**Note**: See ## Alive for the specification of the content.

The summary shall be the last section in the report.
**Note**: See ## Summary for the specification of the content

# TST-plugin_mutate_report_for_human
partof: SPC-plugin_mutate_report_for_human
###

*database content* = {
 * only untested mutants
 * one alive mutant
 * one alive and one killed mutant
 * one alive, one killed and one timeout mutant
 * one alive, one killed, one timeout and one killed by the compiler mutant
}

Verify that the produced report contains the expected result when the input is a database with untested muta

# SPC-plugin_mutate_report_for_tool_integration
partof: REQ-plugin_mutate-report
###

The plugin shall produce a report of live mutants as *gcc compiler warnings* when commanded via the *CLI*.

The plugin shall write the report to stderr.

**Rationale**: This is how gcc do it.

## GCC Compiler Warnings

The format is:
```sh
file:line:column category: text
```

Example:
```sh
foo.cpp: In function ‘int main(int, char**)’:
foo.cpp:4:5: error: expected initializer before ‘return’
     return 'c';
     ^~~~~~
```

Categories are error and warning.

**Note**: There are more categories so update the list when they are found. As of this writing the others aren't important.

## Why?

The assumption made by this requirement is that IDE's that are used have good integration with compilers. They can parse the output from compilers. By outputting the mutants in the same way the only integration of the mutation plugin needed is to add a compilation target in the IDE.
