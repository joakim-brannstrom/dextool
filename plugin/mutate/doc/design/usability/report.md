# REQ-plugin_mutate-report
partof: REQ-plugin_mutate
###

The plugin shall produce a report:
 * that is *easy* to integrate in other tools.
 * that is *easy to read* by a human.

The plugin shall use the *human readable report* as the default report.

**Rationale**: This is based on the assumption that it is important to use defaults for the standalone scenario that make it easy for a human to interpret the results.

## Report Level

The supported report levels are:
 * summary
 * alive
 * all

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

 * Develop a statistical model for how potentially how many bugs there are left in the program that has not been discovered by tests.
 * Should the checksum be used when reporting mutations?
   It is probably a bad idea to "stop" reporting because the source code is not always accessible.
   But the user should be informed that the content is different.
 * Separate the mutation time in compiling SUT+tests and executing tests.

# SPC-plugin_mutate_report_for_human
partof: REQ-plugin_mutate-report
###

The plugin shall produce a report in markdown format when commanded via the *CLI*.

## Why?

Markdown is chosen because there exist many tools to convert it to other formats.
It is also easy for a human to read in the raw form thus it can be used as the default *console* report.

### Git Diff like Report

The user may want the output to be like `git diff`. But keep in mind that this is an *information leak* of the source code which may prohibit its usage when publishing to content systems so should be controllable by the user.

Decision: Not needed. The tool integration can be used for this.

This decision has been partially reverted. It is a bit too limited to only show the mutation subtype that where performed at that mutation point. But after using the markdown report it was determined that the user do not understand the mutation subtypes. It is kind of unreasonable to expect them to memories them.

But the original reason for not implementing it is still valid. Thus a window of ~7 characters are used. For most mutations this is is actually not any more leak of information than it was before. For those mutations that remove source code or replaces large chunks a window that display at most 7 characters is used.

# SPC-plugin_mutate_report_for_human-cli
partof: SPC-plugin_mutate_report_for_human
###

The command line argument *--level* shall control the *report level* of the human readable report.

The default *report level* shall be *summary*.

The plugin shall support the *report levels* {summary, alive, full}.

## Markdown Chapter Mutants

The report shall use the column order *from*, *to*, *file line:column*, *status*, *id*.

### Why?

A human read a page from left to right. The intent is to keep the most interesting part to the left side.

Without any scientific evidence I (Joakim B) think that the interesting part is what the mutation is (from -> to).
It gives a human a quick way of determining how severe the problem is, if it is an equivalent mutant etc.
When you inspect the report this is probably the part you are looking for.

This is followed by the filename and line:column. When the report is used the reader must be able to find the file the mutation is performed in and where in the file.

The *id* is slightly more interesting than the *status*. It is what uniquely identify a mutation which is used for other things such as marking a mutant as equivalent.

The least interesting is the status. I think that the normal report mode is *alive* which then mean that the status will be filled with "alive". A column which all have the same value is totally uninteresting.

## Summary

The report shall contain a summary of the mutation testing.

The summary shall contain the following information:
 * number of untested mutants
 * number of alive/killed/timeout mutants
 * the sum of the mutants (alive+killed+timeout)
 * the mutation score
 * the time spent on testing alive/killed/timeout mutants in a human readable format (days/hours/minutes/seconds...)
 * the total time spent on mutation testing

The plugin shall calculate a prediction as a date and absolute time for when the current running mutation is done when producing a report and there are any mutants left to test.

**Rationale**: The user is interested in when the mutation is finished because it can take a long time to go through all mutations. All the data to do a simple *mean* approximation is available.

The summary shall contain mutation metrics of the time spent on mutation testing.

## Alive

The report shall contain the location of alive mutations.

A location for a mutant shall containg the following information:
 * the mutation ID
 * the status of the mutant (alive, unknown etc)
 * the file location
    * the path to the file
    * the line and column

The summary shall be the last section in the report.

**Note**: See ## Summary for the specification of the content

**Rationale**: This requirement is based on the assumption that the user is first interested in reading the summary of the mutation testing. By printing the summary last the user do not have to scroll in the console. This is though inverted if the user renders the markdown report as a webpage. Then the user probably want the summary at the top.

### Alive Statistics

The report shall contain the statistics of the alive mutations.

The statistics shall on the original -> mutation:
 * total of that kind
 * percentage of the total
 * textual description of from -> to

The statistics shall be sorted by the count column.

## Full

The report shall contain the location of all mutations.

**Note**: See ## Alive for the specification of the content.

The summary shall be the last section in the report.

**Note**: See ## Summary for the specification of the content

# TST-plugin_mutate_report_for_human
partof: SPC-plugin_mutate_report_for_human
###

*database content*
 * only untested mutants
 * one alive mutant
 * one alive and one killed mutant
 * one alive, one killed and one timeout mutant
 * one alive, one killed, one timeout and one killed by the compiler mutant

*report level* = { summary, alive, all }

Verify that the produced report contains the expected result when the input is a database with *database content* and *report level*.

# SPC-plugin_mutate_report_for_tool_ide_integration
partof: REQ-plugin_mutate-report
###

The plugin shall report mutants as *gcc compiler warnings* when commanded via the *CLI*.

The plugin shall filter the reported mutants by the *report level*:
 * *all*. All mutants are reported.
 * otherwise. Alive mutants are reported.

The plugin shall produce a *fixit hint* for each reported mutant.

The plugin shall write the report to stderr.

**Rationale**: The format of the messages are derived from how gcc output when using `-fdiagnostics-parseable-fixits`.

## GCC Compiler Warnings

The format is:
```sh
file:line:column category: text
```

Categories are error and warning.

**Note**: There are more categories so update the list when they are found. As of this writing the others aren't important.

Example:
```cpp
foo.cpp: In function ‘int main(int, char**)’:
foo.cpp:2:9: error: ‘argcc’ was not declared in this scope
     if (argcc > 3)
         ^~~~~
```

Fixit format is (this is directly after the error in the previous example):
```cpp
foo.cpp:2:9: note: suggested alternative: ‘argc’
     if (argcc > 3)
         ^~~~~
         argc
fix-it:"foo.cpp":{2:9-2:14}:"argc"
```

## Why?

The assumption made by this requirement is that IDE's that are used have good integration with compilers. They can parse the output from compilers. By outputting the mutants in the same way the only integration of the mutation plugin needed is to add a compilation target in the IDE.

The fixit hint is intended to make it easy for a user to see how the mutant modified the source code. This is especially important for those cases where there are many mutations for the same line. Some IDE's such as Eclipse do not move the cursor to the column which makes it harder for the human to manually inspect the mutation.

# SPC-plugin_mutate_report_for_tool_integration_format
partof: REQ-plugin_mutate-report
###

The plugin shall report mutants as a *json model* when commanded via the *CLI*.

## JSON Model

The structure of the json file should be an array of files with their mutations:
```json
{
"types": ["array of the mutation types in this report"],
"files": [
    "filename": "filename",
    "checksum": "file checksum as hex",
    "mutants": ["array of mutants"]
]
}
```

Each mutant is:
```json
{
    "id": "unique ID for the mutant",
    "status": "mutation status",
    "kind": "subtype mutation kind",
    "line": "line number starting from 1 in the file",
    "column": "column number starting from the line",
    "begin": "offset in bytes from start",
    "end": "offset in bytes from start, one byte past the last",
    "value": "the mutation as textual representation"
}
```

# SPC-plugin_mutate_report_for_human_plain
partof: REQ-plugin_mutate-report
###

The plugin shall report mutants as *plain text* when commande via the *CLI*.

## Plain Text

This format is defined as:
```
info: $ID $STATUS from '$FROM' to '$TO' in $ABSOLUTE_PATH:$LINE:$COLUMN
```

The intention is that by providing the absolute path it becomes easier for the user to locate the file.
By printing the full code both from and to it becomes easier to find it on the line.
It becomes easier to understand.

# SPC-plugin_mutate_report_as_csv
partof: REQ-plugin_mutate-report
###

The plugin shall report mutants as *CSV* when commanded via the *CLI*.

## CSV

The intent is to make it easy to import the mutant report in e.g. Excel for inspection.

A user will want to write comments to convey to other users his/her thoughts about the mutant.

The columns should be
1. ID
2. Mutation kind as human readable.
3. Textual description of the mutant which make it easy to inspect at a quick glanse.
    From user input it should be something like: 'x' to 'y'.
4. Filename line:column
5. Comment

## Format Specification

This is copied from the phobos module `std.csv`.

 * A record is separated by a new line (CRLF,LF,CR)
 * A final record may end with a new line
 * A header may be provided as the first record in input
 * A record has fields separated by a comma (customizable)
 * A field containing new lines, commas, or double quotes should be enclosed in double quotes (customizable)
 * Double quotes in a field are escaped with a double quote
 * Each record should contain the same number of fields

# TST-plugin_mutate_report_as_csv
partof: SPC-plugin_mutate_report_as_csv
###

As input to the program use a file that contains DCC/DCR mutations.

Verify that the report:
 * has a CSV header
 * contains a report of mutations for each column
 * the last column, comment, shall be empty
