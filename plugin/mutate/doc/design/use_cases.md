# Use Cases {id="req-use_cases"}

This is a meta requirement for those that are traceable to use cases.

An important aspect is ease of use in day-to-day development. When verification
is performed late in the development process, one discovers generally a huge
amount of problems, and fixing them requires a tremendous effort; it is
sometimes extremely difficult to do when the software has already gone through
various validation phases that would be ruined by massive corrections.

When the tool is integrated into the development environment programmers must
be able to run it routinely each time they develop new modules or modify
existing ones. Ideally as part of the code compile step. The sooner checking is
performed in the development process, the better.

# Early Validation {id="req-early_validation"}

[partof](#req-plugin_mutate-use_case)

This plugin should be easy to use in the day-to-day development.

The plugin should be _fast_ when the changes in the code base are *small*.

The plugin should be _fast_ when performing whole program mutation.
**NOTE**: will require scaling over a computer cluster.

The plugin should produce a detailed report for the user to understand what
mutations have been done and where.

The plugin should on request visualize the changes to the code.
**NOTE**: produce the mutated source code.

The plugin should be easy to integrate with an IDE for visual feedback to the
user.

# Inspection of Test Procedures {id="req-inspection_of_test_proc"}

[partof](#req-plugin_mutate-use_case)

This plugin should replace or simplify parts of the inspection as required by
DO-178C.

The type of mutations to implemented should be derived and traced to the
following statement and list.

The inspection should verify that the test procedures have used the required
test design methods in DO-178C:
 * Boundary value analysis,
 * Equivalence class partitioning,
 * State machine transition,
 * Variable and Boolean operator usage,
 * Time-related functions test,
 * Robustness range test design for techniques above

See [@softwareVerAndVal] for inspiration.

## Note
It is costly to develop test cases because inspection is used to verify that
they adhere to the test design methods by manual inspection. The intention is
to try and automate parts or all of this to lower the development cost and at
the same time follow DO-178C.

## Note 2
It may not be feasible to completely replace an activity. But parts of them
should be possible. One that is currently being explored is to ensure a certain
minimal quality of test cases.
 * Test cases must verify *something*. A test case that do not kill any mutant
   is probably a junk test.
 * Test cases that fully overlap what they test. Test cases that kill exactly
   the same set of mutants are probably equivalent. One of them is probably
   redundant.

# Test Design Metric {id="req-test_design_metric"}

[partof](#req-inspection_of_test_proc)

The plugin should produce metrics for how well the design methods in
[[REQ-inspection_of_test_proc]] has been carried out.

Regarding code coverage:
 * The modified condition / decision coverage shows to some extent that boolean
   operators have been exercised. However, it does not require the observed
   output to be verified by a testing oracle.

Regarding mutation:
 * By injecting faults in the source code and executing the test suite on all
   mutated versions of the program, the quality of the requirements based test
   can be measured in mutation score. Ideally the mutation operations should be
   representative of all realistic type of faults that could occur in practice.

# Incremental Mutation {id="spc-incremental_mutation"}

[partof](#req-early_validation)

The plugin shall support incremental mutation.

A change of one statement should only generate mutants for that change.

A change to a file should only generate mutants derived from that file.

## Notes
The user will spend time on performing a manual analysis of the mutants.

To make it easier for the user it is important that this manual analysis can be
reused as much as possible when the SUT changes.

A draft of a workflow and architecture would be.
 * The user has a report of live mutants.
 * The user goes through the live mutants and mark some as equivalent mutations.
 * The result is saved in a file X.
 * Time goes by and the SUT changes in a couple of files.
 * The user rerun the analyzer.
     The analyzer repopulates the internal database with new mutations for the changed files.
 * The user run the mutant tester. The mutant tester only test those mutations
   that are in the changed files.
 * The user import the previous analysis from file X into Dextool.
 * The user export a mutation result report to file Y (same fileformat as X).
 * The user only has to go through and determine equivalence for the new mutations.

# Understand Analysis {id="req-uc_understand_analysis"}

[partof](#req-early_validation)

The user wants help to understand what is being analyzed and mutated. (1)

The user wants to understand the acronyms for the mutation operators. (2)

## Why? (1)

It has been observed that it is hard for a user to understand this when the
user uses symlinks.  On one hand the plugin try to protect the user from rogue
symlinks that point "outside" the e.g. a git repo. But on the other hand
resolving the real path for symlinks makes it hard for an user that has
symlinks to the source code from where they are building.

Do not underestimate this point and the frustration it creates for an user. It
leads to considerable irritation. To such a degree that the user will not use
the tool.

## Why? (2)

Users have complained that they do not understand what e.g. LCR/ROR mean. They
want it spelled out.  The goal should be to provide enough information for the
user to easier understand the report.  They shouldn't need to look up a wiki or
other things. The tool should help them understand.

# Characteristics of Good Tests {id="req-uc_characteristics_of_good_tests"}

Good test cases satisfy the following criterias [@rieson178C]:

1. “It has a reasonable probability of catching an error.” Tests are designed
   to find errors - not merely to prove functionality. When writing a test one
   must consider how the program might fail.
2. “It is not redundant.” Redundant tests offer little value. If two tests are
   looking for the same error, why run both?
3. “It is the best of its breed.” Tests that are most likely to find errors are
   most effective.
4. “It is neither too simple nor too complex.” Overly-complex tests are
   difficult to maintain and to identify the error. Overly-simple tests are
   often ineffective and add little value.

## Discussions

How can mutation testing be used to help provide help to the developer for the
test case criterias?

The first that needs to be done is to track what test cases killed what
mutants. This gives a rich, deep information about the relationship between the
source code and test cases.

### Criteria 1

Report how many mutants a test case kill.

### Criteria 2

The most obvious is to find test cases that kill exactly the same mutants.
These are the *obviously* redundant test cases.

Another interesting report is to calculate a minimal set of test cases that
would result in the correct mutation score. This would find test cases that do
not fully overlap but still do not contribute to the overall verification
effort.

#### Note

Experience from using this technique has show that parameterized test cases
[@googleTest] that are used to test the boundary values have a high probability
of not being unique *enough* and thus end up in a report of overlapping test
cases. No further studies have been done on this subject.

An interesting study would be to see if these test cases are redundant and thus
is an indication of an erroneous boundary value analysis.  I do not believe so
but it should be shown with data that such is the case.

Be careful on this subject because it must be remembered that mutation testing
is done on the source code. Just because it at one moment in the project mean
that the source code and thus the test cases overlap do not mean it will be
that case in the future.

Experience have further shown that 100% overlap between test case rarely happen
besides the above noted case.

What has been noted is that after a certain level of mutation score have been
reached when doing requirement based testing new test cases stop contributing
to the mutation score. In other words that test cases that are added do not add
to the verification.

### Criteria 3

This is harder to interpret what [@rieson178C] mean. My interpretation is that
a test case that kill many mutants at a limited source code location is the
*best* test case.

In contrary a test case that kill many mutants but spread out in the
application is a fragile test case. Most changes to the source code will lead
to that particular test case failing but with no clear meaning why it failed.

### Criteria 4

The simple part is most probably covered by reporting test cases that kill few
mutants.  A test case that kill 1-2 mutants are *most probably* far too
simplistic in its nature.

I do not think that the complex part can be automatically covered. This is best
handled by a pull request work flow with continuous reviews.
