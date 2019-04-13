# REQ-report
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

# SPC-report_for_human
partof: REQ-report
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

# SPC-report_for_human-cli
partof: SPC-report_for_human
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

# TST-report_for_human
partof: SPC-report_for_human
###

*database content*
 * only untested mutants
 * one alive mutant
 * one alive and one killed mutant
 * one alive, one killed and one timeout mutant
 * one alive, one killed, one timeout and one killed by the compiler mutant

*report level* = { summary, alive, all }

Verify that the produced report contains the expected result when the input is a database with *database content* and *report level*.

# SPC-report_for_tool_ide_integration
partof: REQ-report
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

# SPC-report_for_tool_integration_format
partof: REQ-report
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

# SPC-report_for_human_plain
partof: REQ-report
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

# SPC-report_as_csv
partof: REQ-report
###

The plugin shall report mutants in the *CSV format* when commanded via the *CLI*.

**Note**: The standard for *CSV format* is somewhat unclear. This plugin try to adher to what wikipedia states about the format.

## Requirements for Rapid User Understanding

**Rationale**: The intention with the *textual description* field is to make it possible for the user to identify the mutant in the source code. This has been reported from the user as a problem when trying to understand the RORp and DCR mutants. As a side effect this may even make it possible for the user to classify a mutant by just looking at this field.

The plugin shall wrap each field in double quotes when printing a CSV line.

**Rationale**: This makes it somewhat easier to implement. It also makes it possible to embedded newlines which is useful for the *textual description* field.

The plugin shall limit the *textual description* field to 255 characters when printing a CSV line.

**Rationale**: 255 characters is assumed to be *enough* for the user to clearly identify and *somewhat* understand the mutant. Users have reported that LibreOffice Calc do not handle long lines well because the scrolling becomes horizontally unresponsive. Thus the limiting is further motivated. It has been tried to use a limit of 512 characters but that was too much.

The plugin shall remove double quotes from the *original* and *mutated* part of the *textual description* field when printing a CSV line.

**Rationale**: The problem with quotes are that they are somewhat more cumbersome to implement so by removing them the implementation is simpler. This shouldn't inhibit the readability.

## CSV

The intent is to make it easy to import the mutant report in e.g. Excel for inspection.

A user will want to write comments to convey to other users his/her thoughts about the mutant.

The columns should be
1. ID
2. Mutation kind as human readable.
3. Textual description of the mutant which make it easy to inspect at a quick glance.
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

From wikipedia regarding the double quotes:
 * Each of the embedded double-quote characters must be represented by a pair of double-quote characters.
    * 1997,Ford,E350,"Super, ""luxurious"" truck"

# TST-report_as_csv
partof: SPC-report_as_csv
###

As input to the program use a file that contains DCC/DCR mutations.

Verify that the report:
 * has a CSV header
 * contains a report of mutations for each column
 * the last column, comment, shall be empty

# REQ-report_mutation_score
partof: REQ-report
###

The plugin shall calculate the mutation score based on the number of unique source code mutations of the specified kind(s).

## Rationale

None of these assumptions are verified.

This is based on the idea that a developer is more interested in the actual changes in the source code. The developer is less interested in the "academically" correct way of calculating mutations.

A side effect of this is that a problem that can occur is that when combining multiple mutation operators it can result in duplications of source code changes. By doing it this way, on the source code changes, the score should be more "stable" and "truer".

# REQ-report_test_group
partof: REQ-report
###

The plugin shall construct a *test case group* from a regex when reading the configuration file.

The plugin shall report the *group mutation score* when reporting.

TODO: improve the requirements. They are too few and badly written.
What they try to say is that the user specify a regex in the configuration file.
One regex == one test case group.
A test case is part of a group if it matches the regex. Simple!
Then this is reported to the user.

## Rationale

The user have a high level requirement that they want to get a quality metric
for how well it is tested in the software. This could e.g. be a use case. Lets
call it an use case henceforth.

During the implementation of this use case a bunch of test cases have been
implemented. These test cases have, obviously, been implemented with the
intention to verify the parts of the implementation that are related to the use
case..

It can thus be reasoned that this *group* of test cases collectively try to
verify the implementation of the use case.

Assume that if a test case in this *group* kill a mutant at a mutation point
that this mutation point is part of the use case. In other words if a test case
verify **an** aspect at a mutation point it is assumed that the whole mutation
point represent behavior that is part of the use case. Thus the test case group
should verify **all** aspects at this mutation point.

**Definition**: Owned Mutation Point. A mutation point that has one or more
mutants that where killed by a group test case.

**Definition**: Test Case Group. Test cases that collectively verify the
implementation of a use case.

**Definition**: Group Kill. Mutants that has been killed by a test case that is part of a *test case group*.

The Group Mutation Score is calculated as:

(Group Kill) / (Total mutants in all Owned Mutation Points).

This assumption, of course, is not always true. This is obvious if one consider
mutation points that multiple use cases affect. But if the assumption is true
most of the time it can be further reasoned that there is a correlation between
this *group mutation score* and the *test quality* of the test suite in
relation to the use case.

# REQ-report_short_term_view
partof: REQ-report
###

The plugin shall report the test cases that killed mutants in the *externally supplied diff* when generating the report.

The plugin shall support the unified diff format.

## Explanation: Externally Supplied Diff

The user of the plugin construct a diff in one of the supported formats. The diff is given to the plugin when it generates the report.

**Note**: The current design reads it from stdin to make it easy to integrate with git. Example `git diff HEAD~|dextool mutate report --style html --diff-from-stdin`.

**Note**: May be advantageous to support reading from a separate file to ease the integration for a user.

TODO: reformulate this chapter into a use case and/or design requirement.

## Purpose

The purpose of the short term view is to show to an individual/few developers how mutation testing relate to *the developers* code changes.
It is important that the view do not present too much information so the developer become overwhelmed and thus give up [@googleMutationTesting2018].

 * the developers have the changes fresh in memory.
 * a developer that has *changed* a part of a code *probably* feel like he/she owns it. A developer that feel that he/she own something are more likely to take action to improve the quality.

## Cost Estimate

It is useful information when trying to deduce how a code change (bugfix/new feature etc)

 * Affects requirements and thus which ones *may* be affected and need an update.
 * What manual tests *should* be performed because the change affects those.
 * Improve the time it takes to do a cost estimate of the formal/informal activities that need to be performed for the change.
   The plugin gives a report of the affected TCs, **automatically**.
   The user check the trace data (TC->"verification case specification"->"SW req."->"System req.").
   The tracing is used as input to the cost estimation for what formal documents are affected and to what magnitude.

## Background
See [@googleMutationTesting2018]. The paper coin the term *productive mutant*.

**Assumption 1**: A developer feels that they *own* a part of code if they recently made changes to that part.

# REQ-report_long_term_view
partof: REQ-report
###

TODO: write requirements.

## Background

See [@googleMutationTesting2018].

This is an interpretation of the paper. This view focus on presenting information that a team can take action on.

**Assumption 1**: The team is responsible, collectively, for the long term maintenance of the SUT.
Should the mutant be be suppressed? Fixed? Is this a potentially hidden bug?

**Assumption 2**: The team feel that they own the *whole* code base. They feel *responsible*. This creates an incitement for the team to *act*.

**Assumption 3**: There is a correlation between the mutants that has survived the longest in the system, over time, and where there are potential problems in the SUT.
Problems such as hidden bugs, hard to maintain etc.

## How

Present the 10 mutants (configurable) that has survived the longest in the system.

With a link, time when they where discovered, how many times they have been tested when the last test where done etc.

# REQ-suppress_mutants
partof: REQ-report
###

The user wants to be able to disregard equivalent mutants and undesirable mutants when assessing test case quality.

**Rationale**: When going through the mutation report there are some that doesn't matter (logging) or others that are *more or less* equivalent mutants. The intention then is to let the user mark these mutants such that they do not count against the score.

The user wants to categories suppressed mutants when they are marked.

**Note**: User feedback is that the categories should be case insensitive so a case "change" doesn't lead to the mutant being placed in a new category. Keep it simple and avoid common mistakes that can occure by forcing the sorting of suppressed mutants into categories to be case insensitive.

The user wants to be able to add a comment to suppressed mutants.

**Rationale**: The intention is to use these categories and comments when presenting a view of all suppressed mutants in the program to make it easier to inspect. It is to move the discussion from "Why is this mutant suppressed? I don't understand anything!" to "This mutant is of type A and has a comment explaining why it is ignored. The comment seems rationale when considering the category the mutant is part of.".

The user wants to add a description to the categories so it is possible to explain what it is, when it is prudent to use, restrictions on use etc. The user then expects this description to be part of the report of the suppressed mutants.

# SPC-report_suppress_mutants
partof: REQ-suppress_mutants
###

The plugin shall produce a HTML report of the suppressed mutants.

The plugin shall sort the suppress mutants in the HTML report by their category.

The plugin shall use the alive color for suppressed mutants in the HTML view.

**Note**: This requirement though conflicts with a usability feedback that it is not possible to *see* if a mutant is suppressed or not. As the user said:
 * "Did I put the NOMUT at the correct place?"
 * "Is dextool working correctly?"

Thus for the requirement about the color in the HTML view an additional requirement is need:

The plugin shall visualize a suppressed mutant with the "nomut" attribute.

## Note

There is a psychology game to play with the user here when it comes to visualizing the mutants that are marked. We do not want to encourage the user to sprinkle suppressions all over the code base. If we look at the design of clang-tidy we can see that at the end of its report it prints how many warnings where suppressed. We want to do something like that too. Let the user be able to mark mutants but discourage the behavior. Some of the tools to use to avoid this is to have an offensive color for suppressed mutants. Another tool is how the statistics are presented and help texts.

# SPC-count_suppressed_mutants
partof: REQ-suppress_mutants
###

The plugin shall count suppressed mutants as killed when calculating the mutation score.

# REQ-overlap_between_test_cases
partof: REQ-report
###

The user have a test suite divided in two parts, *high quality* (a) tests and *the rest* (b).

The user is wondering if there are any tests in (b) that are redundant because those aspects are already verified by (a). The test, in other words, do not contribute to the test effectiveness. It is just a maintenance burden that cost money.

The user is wondering if there are tests in (b) that verify a unique aspect of the software and thus should be moved from (b) to (a).

# SPC-report_minimal_set
partof: REQ-overlap_between_test_cases
###

The plugin shall calculate a minimal set of test cases that produce the same mutation score as if all test cases where used.

The plugin shall produce a HTML report with the sections minimal set and the rest.

## Algorithm

The data is:

$TC_x = \{ KM \}$

$score = \{ KM \}$

 * KM = killed mutant. A unique ID distinguish mutants from each other.
 * TC\_x = set of mutant IDs that test case *x* killed.
 * score = set of mutant IDs that result in the current mutation score.

The minimal set is calculated by as:

1. $minset_0 = \emptyset$
   $score = \emptyset$
2. $minset_1 = \{ TC_0 \} \cap minset_0$
   $score_1 = score_1 \cap TC_0$
3. $minset_2 = \{ TC_1 \} \cap minset_1$
   $score_2 = score_2 \cap TC_1$
4. if $|minset_1| = |minset_2|$ then the minimal set is $minset_1$. Exit. Otherwise repeat step 2-3.

## Note

The algorithm is heuristic because it depend on in which order the test cases are chosen. A different order will most likely result in a different minimal set. It is important that the user of the tool understand this.

The calculated minimal set is further dependent on the mutation operators that are used. Another view of it is that the mutation operators are sample points in the software that the test suites *can* kill. If there are too few or missing samples it can lead to a shewed result. On the other hand this can be used as a technique by the tester to understand different aspects of the test suite. Such as how similare test cases that verify logical assumptions in the software are to each other by looking at the *LCR* and *DCR* mutation operators.

# SPC-report_test_case_similarity
partof: REQ-overlap_between_test_cases
###

The plugin shall calculate the similarity between all test cases.

The plugin shall produce a HTML report with a section for each TC displaying the top X test cases that it is similare to.

## Algorithm

The data is:

$TCx = \{ KM \}$

 * KM = killed mutant. A unique ID distinguish mutants from each other.
 * TCx = set of mutant IDs that test case *x* killed.

The algorithm used to calculate the similarity is the *jaccard similarity* metric.

$|TCx \cap TCy| / |TCx \cup TCy|$

The number of items in the intersection divided by the number of items in the union.

## Note

The algorithm used is the *jaccard similarity* metric. The desired properties which lead to this choice where:
 * the result is in the range 0.0 to 1.0. The closer to 1.0 the more similar the test cases are to each other.
 * its intention is to compare sets with each other.

The algorithm *gap weighted similarity* where briefly used but it had the following problems:
 * the result where in the range 0 to infinity. The higher the more similar. The values could end up in the range of millions. This mean it is harder for a user to interpret the result at a glance.
 * it seems to be an algorithm more suited for comparing text than sets.
 * the data for a TC never contains duplicate mutants thus the *gap weighted similarity* which is affected by this is redundant. It just complicates the understanding of how the similarity should be interpreted.
 * the algorithm takes into account the similarity between the subsets but this, I think, isn't of interest. It complicates things. Without data that states that this is needed I can't see a motivation to introduce this complication.
