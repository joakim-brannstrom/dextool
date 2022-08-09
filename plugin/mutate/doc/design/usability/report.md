# Report {id="req-report"}

The plugin shall support producing reports in formats that are:

 * *easy* to integrate in other tools.
 * *easy to read* by a human.

## Why Human Readable Report

The main consumer of the report is a human in the end. A human will need to
understand the information that is presented to them and act. The reporting
should assume that the human is a developer. A developer is always time
constrained, a bit lazy and easily overwhelmed with information. A developer
that opens the report prefer a layout that has easily actionable information
presented to them together with deeper information for when it is needed.

Imagin a CI integration and a pull request workflow. The reviewer of the pull
request gets a link to the mutation report. They want to easily see if there
are some major problems with the pull request that the tool has found.
Preferably without scrolling/moving around so much.

## Why Tool Integration?

A report tailored for a human is often not suitable for machine consumption
therefor at least one other format need to be supported for this case. Its
intent is to make it easy for a user to extend the reporting without modifying
the tool, integrate with other software etc.

## Git Diff like Report

Other tools support producing mutants as diffs and use that as "report".

**Decision**: Not needed. If a user absolutely need it then it can be mimicked
with the tool integration report.  So far no user has requested it because the
human readable report is good enough and easier.

## Report For Human {id="spc-report_for_tool_developer"}
[partof](#req-report)

The plugin shall produce a plain console report when style is *plain*.

### Why?

This is mainly intended to be used either by the tool developers of dextool or
to quickly check e.g. the mutation score. It do not have to be full featured or
anything. The human readable report is intended for that.

## SPC-report_for_tool_ide_integration
[partof](#req-report)

The plugin shall report mutants as *gcc compiler warnings* when style is *compiler*.

The report only need to support reporting all mutants or alive.

**Rationale**: Because the compiler format isn't modifiable thus limited in what it can contain.

The plugin shall produce a *fixit hint* for each reported mutant.

**Rationale**: The format of the messages are derived from how gcc output when
using `-fdiagnostics-parseable-fixits`.

The plugin shall write the report to stderr.

### GCC Compiler Warnings

The format is:
```sh
file:line:column category: text
```

Categories are error and warning.

**Note**: There are more categories so update the list when they are found. As
of this writing the others aren't important.

Example:
```cpp
foo.cpp: In function int main(int, char**):
foo.cpp:2:9: error: argcc was not declared in this scope
     if (argcc > 3)
         ^~~~~
```

Fixit format is (this is directly after the error in the previous example):
```cpp
foo.cpp:2:9: note: suggested alternative: argc
     if (argcc > 3)
         ^~~~~
         argc
fix-it:"foo.cpp":{2:9-2:14}:"argc"
```

### Why?

The assumption made by this requirement is that IDE's that are used have good
integration with compilers. They can parse the output from compilers. By
outputting the mutants in the same way the only integration of the mutation
plugin needed is to add a compilation target in the IDE.

The fixit hint is intended to make it easy for a user to see how the mutant
modified the source code. This is especially important for those cases where
there are many mutations for the same line. Some IDE's such as Eclipse do not
move the cursor to the column which makes it harder for the human to manually
inspect the mutation.

## SPC-report_for_tool_integration_format
[partof](#req-report)

The plugin shall report mutants as a *json model* when style is *json*.

## REQ-report_mutation_score
[partof](#req-report)

The plugin shall calculate the mutation score based on the number of unique
source code mutations of the specified kind(s).

## Rationale

None of these assumptions are verified.

This is based on the idea that a developer is more interested in the actual
changes in the source code. The developer is less interested in the
"academically" correct way of calculating mutations.

A side effect of this is that a problem that can occur is that when combining
multiple mutation operators it can result in duplications of source code
changes. By doing it this way, on the source code changes, the score should be
more "stable" and "truer".

## REQ-report_test_group
[partof](#req-report)

The plugin shall construct a *test case group* from a regex when reading the
configuration file.

The plugin shall report the *group mutation score* when reporting.

TODO: improve the requirements. They are too few and badly written.  What they
try to say is that the user specify a regex in the configuration file.  One
regex == one test case group. A test case is part of a group if it matches the
regex. Simple!  Then this is reported to the user.

### Rationale

The user have a high level requirement that they want to get a quality metric
for how well it is tested in the software. This could e.g. be a use case. Lets
call it an use case henceforth.

During the implementation of this use case a bunch of test cases have been
implemented. These test cases have, obviously, been implemented with the
intention to verify the parts of the implementation that are related to the use
case.

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

**Definition**: Group Kill. Mutants that has been killed by a test case that is
part of a *test case group*.

The Group Mutation Score is calculated as:

(Group Kill) / (Total mutants in all Owned Mutation Points).

This assumption, of course, is not always true. This is obvious if one consider
mutation points that multiple use cases affect. But if the assumption is true
most of the time it can be further reasoned that there is a correlation between
this *group mutation score* and the *test quality* of the test suite in
relation to the use case.

## REQ-report_short_term_view
[partof](#req-report)

The plugin shall report the test cases that killed mutants in the *externally
supplied diff* when generating the report.

The plugin shall support the unified diff format.

### Explanation: Externally Supplied Diff

The user of the plugin construct a diff in one of the supported formats. The
diff is given to the plugin when it generates the report.

**Note**: The current design reads it from stdin to make it easy to integrate
with git. Example `git diff HEAD~|dextool mutate report --style html
--diff-from-stdin`.

**Note**: May be advantageous to support reading from a separate file to ease
the integration for a user.

TODO: reformulate this chapter into a use case and/or design requirement.

### Purpose

The purpose of the short term view is to show to an individual/few developers
how mutation testing relate to *the developers* code changes.  It is important
that the view do not present too much information so the developer become
overwhelmed and thus give up [@googleMutationTesting2018].

 * the developers have the changes fresh in memory.
 * a developer that has *changed* a part of a code *probably* feel like he/she
   owns it. A developer that feel that he/she own something are more likely to
   take action to improve the quality.

### Cost Estimate

It is useful information when trying to deduce how a code change (bugfix/new
feature etc)

 * Affects requirements and thus which ones *may* be affected and need an update.
 * What manual tests *should* be performed because the change affects those.
 * Improve the time it takes to do a cost estimate of the formal/informal activities that need to be performed for the change.
   The plugin gives a report of the affected TCs, **automatically**.
   The user check the trace data (TC->"verification case specification"->"SW req."->"System req.").
   The tracing is used as input to the cost estimation for what formal documents are affected and to what magnitude.

### Background
See [@googleMutationTesting2018]. The paper coin the term *productive mutant*.

**Assumption 1**: A developer feels that they *own* a part of code if they
recently made changes to that part.

## REQ-report_long_term_view
[partof](#req-report)

TODO: write requirements.

### Background

See [@googleMutationTesting2018].

This is an interpretation of the paper. This view focus on presenting
information that a team can take action on.

**Assumption 1**: The team is responsible, collectively, for the long term
maintenance of the SUT.  Should the mutant be be suppressed? Fixed? Is this a
potentially hidden bug?

**Assumption 2**: The team feel that they own the *whole* code base. They feel
*responsible*. This creates an incitement for the team to *act*.

**Assumption 3**: There is a correlation between the mutants that has survived
the longest in the system, over time, and where there are potential problems in
the SUT.  Problems such as hidden bugs, hard to maintain etc.

### How

Present the 10 mutants (configurable) that has survived the longest in the
system.

With a link, time when they where discovered, how many times they have been
tested when the last test where done etc.

## REQ-suppress_mutants
[partof](#req-report)

The user wants to be able to disregard equivalent mutants and undesirable
mutants when assessing test case quality.

**Rationale**: When going through the mutation report there are some that
doesn't matter (logging) or others that are *more or less* equivalent mutants.
The intention then is to let the user mark these mutants such that they do not
count against the score.

The user wants to categories suppressed mutants when they are marked.

**Note**: User feedback is that the categories should be case insensitive so a
case "change" doesn't lead to the mutant being placed in a new category. Keep
it simple and avoid common mistakes that can occur by forcing the sorting of
suppressed mutants into categories to be case insensitive.

The user wants to be able to add a comment to suppressed mutants.

**Rationale**: The intention is to use these categories and comments when
presenting a view of all suppressed mutants in the program to make it easier to
inspect. It is to move the discussion from "Why is this mutant suppressed? I
don't understand anything!" to "This mutant is of type A and has a comment
explaining why it is ignored. The comment seems rationale when considering the
category the mutant is part of.".

The user wants to add a description to the categories so it is possible to
explain what it is, when it is prudent to use, restrictions on use etc. The
user then expects this description to be part of the report of the suppressed
mutants.

The user wants to be able to mark a mutant via an admin-command and provide a
rationale for why the mutant was marked.

**Rationale**: The ability to mark mutants via a commando removes the need to
modify code (inserting a comment) in order to suppress a mutant. This is useful
for example inspected code that *should* not be modified. By providing a
rationale, the user can specify exactly the reason and motivation behind the
marking. It also allows the user to chose whether or not the mutant should be
included in the final score.

**Note**: This is a user-based requirement. Marking mutants manually is both
tedious and unstable if the analyze phase is intended to be run again. However,
this also gives the user the ability to mark mutants with any status. This
could be dangerous in the long term, if the tool is promoting suppression.

## SPC-report_suppress_mutants
[partof](#req-suppress_mutants)

The plugin shall produce a HTML report of the suppressed mutants.

The plugin shall sort the suppress mutants in the HTML report by their category.

The plugin shall use the alive color for suppressed mutants in the HTML view.

**Note**: This requirement though conflicts with a usability feedback that it
    is not possible to *see* if a mutant is suppressed or not. As the user said:
 * "Did I put the NOMUT at the correct place?"
 * "Is dextool working correctly?"

Thus for the requirement about the color in the HTML view an additional
requirement is need:

The plugin shall visualize a suppressed mutant with the "nomut" attribute.

### Note

There is a psychology game to play with the user here when it comes to
visualizing the mutants that are marked. We do not want to encourage the user
to sprinkle suppressions all over the code base. If we look at the design of
clang-tidy we can see that at the end of its report it prints how many warnings
where suppressed. We want to do something like that too. Let the user be able
to mark mutants but discourage the behavior. Some of the tools to use to avoid
this is to have an offensive color for suppressed mutants. Another tool is how
the statistics are presented and help texts.

## SPC-count_suppressed_mutants
[partof](#req-suppress_mutants)

The plugin shall count alive, suppressed mutants as equivalent when calculating
the mutation score.

### Note

The formula for the mutation score is `killed / (total - equivalent)`.

### Why?

Previously the suppressed mutants where counted as killed. After discussing the
matter we revised the decision. This is because a suppressed mutant is an
*unproductive* mutant.

An *unproductive* mutant encompasses two things. It is either:

 * never intended to be killed because the mutant is *bad*. The tool should,
   according to the user, not produce them.
 * the user *kills* the mutant by inspecting that it is OK as is but the user
   do not want to write a test case to kill it.

It isn't possible to distinguish these two cases from each other without
further annotations which would complicate the tool unnecessarily. By changing
the formula for calculating the mutation score it is kind a solved because the
score then reflects *only* those mutants that aren't debatable if they are good
or bad.

## REQ-overlap_between_test_cases
[partof](#req-report)

The user have a test suite divided in two parts, *high quality* (a) tests and
*the rest* (b).

The user is wondering if there are any tests in (b) that are redundant because
those aspects are already verified by (a). The test, in other words, do not
contribute to the test effectiveness. It is just a maintenance burden that cost
money.

The user is wondering if there are tests in (b) that verify a unique aspect of
the software and thus should be moved from (b) to (a).

The user wants to be able to inspect the uniqueness and overlap between test
cases at detail to discern how and if they could be changed to be of higher
quality.

## SPC-report_minimal_set
[partof](#req-overlap_between_test_cases)

The plugin shall calculate a minimal set of test cases that produce the same
mutation score as if all test cases where used.

The plugin shall produce a HTML report with the sections minimal set and the rest.

### Algorithm

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

### Note

The algorithm is heuristic because it depend on in which order the test cases
are chosen. A different order will most likely result in a different minimal
set. It is important that the user of the tool understand this.

The calculated minimal set is further dependent on the mutation operators that
are used. Another view of it is that the mutation operators are sample points
in the software that the test suites *can* kill. If there are too few or
missing samples it can lead to a shewed result. On the other hand this can be
used as a technique by the tester to understand different aspects of the test
suite. Such as how similar test cases that verify logical assumptions in the
software are to each other by looking at the *LCR* and *DCR* mutation
operators.

## SPC-report_test_case_similarity
[partof](#req-overlap_between_test_cases)

The plugin shall calculate the similarity between all test cases.

The plugin shall produce a HTML report with a section for each TC displaying
the top X test cases that it is similar to.

### Algorithm

The data is:

$TCx = \{ KM \}$

 * KM = killed mutant. A unique ID distinguish mutants from each other.
 * TCx = set of mutant IDs that test case *x* killed.

The algorithm used to calculate the similarity is a modified *jaccard similarity* metric.

$|TCx \cap TCy| / |TCx|$

The number of items in the intersection divided by the number of items in the left side.

### Note

The algorithm used is a modified *jaccard similarity* metric. The desired property which lead to this choice where:
 * the result is in the range 0.0 to 1.0. The closer to 1.0 the more similar the test cases are to each other.
 * its intention is to compare sets with each other.
 * the metric is higher the more of a subset one side is to the other.

The algorithm *jaccard similarity* metric where briefly used but discarded
because it couldn't capture the subset similarity which is one of the key
factors that the user asked for. The positive fact though of the *jaccard
similarity* is that the metric is bidirectional. It doesn't matter in which
order the sets are compared.

The algorithm *gap weighted similarity* where briefly used but it had the following problems:
 * the result where in the range 0 to infinity. The higher the more similar.
   The values could end up in the range of millions. This mean it is harder for
   a user to interpret the result at a glance.
 * it seems to be an algorithm more suited for comparing text than sets.
   the data for a TC never contains duplicate mutants thus the *gap weighted
   similarity* which is affected by this is redundant. It just complicates the
   understanding of how the similarity should be interpreted.
 * the algorithm takes into account the similarity between the subsets but
   this, I think, isn't of interest. It complicates things. Without data that
   states that this is needed I can't see a motivation to introduce this
   complication.

## REQ-uc_formal_verification_surviving_mutant
[partof](#req-plugin_mutate)

A formal verification process will have a process for how to handle mutants
that survive.

An example of how that could look is as follow:

    > For high criticality software, surviving mutants of type SDL, DCR, LCR,
    > LCRb must be resolved in one of the following ways.
    >  1. Remove code
    >  2. Correct tests
    >  3. Change or add requirements and tests
    >  4. Analysis and justifications for e.g defensive programming which is untestable.

For approach **2** and **3** the user needs to find out *how to kill a
surviving mutant*.

## SPC-test_case_near_surviving_mutant
[partof](#req-uc_formal_verification_surviving_mutant)

The plugin shall present the test cases that killed mutants at each mutation
point in the file view when generating a html report.

## Design

Present the test cases that killed a mutant that is *near* the surviving
mutant.

When inspecting a surviving mutant in the html code view the user would like a
convenient way to find test cases that killed a *near* mutant. For example if:

    > a || b -> false

was killed but

    > a || b -> true

survived The user would like to know which test case(s) that killed the first
mutation so that they can use it to assess the surviving mutant. One such
assessment could be to extend one of the test suites that killed the first
mutant so it kills the second mutant.

## REQ-uc_overview_of_mutation_score
[partof](#req-plugin_mutate)

It is important for a user to be able to *quickly* assess the quality of the
test suite to find what parts of an application needs more testing.

The layout of the source code is often times ordered in directories for each
component. It would be helpful if the score that is presented to the user can
be summaries in some way that it maps back to the source code layout.

## REQ-uc_remove_redundant_tests
[partof](#req-plugin_mutate)

The user wants to be able to identify what mutants that a test case are alone
of killing as to assert how *unique* the test case is.  This can for example be
a test case that is hard to maintain and the developer have a suspicion that
the test case may be removed because other test cases already test what this
*bad* test case test. But the developer do not have any facts that underpins
this suspicion.

By presenting a report of the test cases and what mutants they alone kill it
becomes possible for the developer to look at this reports.

## SPC-test_case_uniqeness_report
[partof](#req-uc_remove_redundant_tests)

The plugin shall produce a report that for each test case contains those
mutants that only that test case kill when commanded.

## Use Case: Trend {id="req-report-trend"}

The user wants to see how the mutation score is trending for the test suite
over time. Is it going up/down or just keeping steady? This information helps
the user to determine what action, if any, to take. It is expected to e.g.
clearly show that if new functionality is added but no tests then the trend is
going down.

### Trend Implementation {id="spc-report-trend"}
[partof](#req-report-trend)

A one dimensional kalman filter will produce a prediction and smooth out high
frequency jitter (process variance of 0.01).

By running the kalman filter on the mutants in the order that they are tested
(oldest to latest) should give a predicted mutation score of where the test
suite is heading.
