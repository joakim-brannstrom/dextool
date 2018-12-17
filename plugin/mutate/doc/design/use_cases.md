# REQ-plugin_mutate-use_case
This is a meta requirement for those that are traceable to use cases.

An important aspect is ease of use in day-to-day development. When verification is performed late in the development process, one discovers generally a huge amount of problems, and fixing them requires a tremendous effort; it is sometimes extremely difficult to do when the software has already gone through various validation phases that would be ruined by massive corrections.

When the tool is integrated into the development environment programmers must be able to run it routinely each time they develop new modules or modify existing ones. Ideally as part of the code compile step. The sooner checking is performed in the development process, the better.

# REQ-early_validation
partof: REQ-plugin_mutate-use_case
###
This plugin should be easy to use in the day-to-day development.

The plugin should be _fast_ when the changes in the code base are *small*.

The plugin should be _fast_ when performing whole program mutation.
**NOTE**: will require scaling over a computer cluster.

The plugin should produce a detailed report for the user to understand what mutations have been done and where.

The plugin should on request visualize the changes to the code.
**NOTE**: produce the mutated source code.

The plugin should be easy to integrate with an IDE for visual feedback to the user.

# REQ-inspection_of_test_proc
partof: REQ-plugin_mutate-use_case
###
This plugin should replace or simplify parts of the inspection as required by DO-178C.

The type of mutations to implemented should be derived and traced to the following statement and list.

The inspection should verify that the test procedures have used the required test design methods in DO-178C:
 * Boundary value analysis,
 * Equivalence class partitioning,
 * State machine transition,
 * Variable and Boolean operator usage,
 * Time-related functions test,
 * Robustness range test design for techniques above

See [@softwareVerAndVal] for inspiration.

## Note
It is costly to develop test cases because inspection is used to verify that they adhere to the test design methods by manual inspection. The intention is to try and automate parts or all of this to lower the development cost and at the same time follow DO-178C.

## Note 2
It may not be feasible to completely replace an activity. But parts of them should be possible. One that is currently being explored is to ensure a certain minimal quality of test cases.
 * Test cases must verify *something*. A test case that do not kill any mutant is probably a junk test.
 * Test cases that fully overlap what they test. Test cases that kill exactly the same set of mutants are probably equivalent. One of them is probably redundant.

# REQ-test_design_metric
partof: REQ-inspection_of_test_proc
###
The plugin should produce metrics for how well the design methods in [[REQ-inspection_of_test_proc]] has been carried out.

Regarding code coverage:
 * The modified condition / decision coverage shows to some extent that boolean operators have been exercised. However, it does not require the observed output to be verified by a testing oracle.

Regarding mutation:
 * By injecting faults in the source code and executing the test suite on all mutated versions of the program, the quality of the requirements based test can be measured in mutation score. Ideally the mutation operations should be representative of all realistic type of faults that could occur in practice.

# SPC-incremental_mutation
partof: REQ-early_validation
###
The plugin shall support incremental mutation.

A change of one statement should only generate mutants for that change.

A change to a file should only generate mutants derived from that file.

## Notes
The user will spend time on performing a manual analysis of the mutants.

To make it easier for the user it is important that this manual analysis can be reused as much as possible when the SUT changes.

A draft of a workflow and architecture would be.
 * The user has a report of live mutants.
 * The user goes through the live mutants and mark some as equivalent mutations.
 * The result is saved in a file X.
 * Time goes by and the SUT changes in a couple of files.
 * The user rerun the analyzer.
     The analyzer repopulates the internal database with new mutations for the changed files.
 * The user run the mutant tester. The mutant tester only test those mutations that are in the changed files.
 * The user import the previous analysis from file X into Dextool.
 * The user export a mutation result report to file Y (same fileformat as X).
 * The user only has to go through and determine equivalence for the new mutations.

# REQ-uc_understand_analyze
partof:
###

The user wants to help to understand what is being analyzed and mutated. (1)

The user wants to understand the acronyms for the mutation operators. (2)

## Why? (1)

It has been observed that it is hard for a user to understand this when the user uses symlinks.
On one hand the plugin try to protect the user from rogue symlinks that point "outside" the e.g. a git repo. But on the other hand resolving the real path for symlinks makes it hard for an user that has symlinks to the source code from where they are building.

Do not underestimate this point and the frustration it creates for an user. It leads to considerable irritation. To such a degree that the user will not use the tool.

## Why? (2)

Users have complained that they do not understand what e.g. LCR/ROR mean. They want it spelled out.
The goal should be to provide enough information for the user to easier understand the report.
They shouldn't need to look up a wiki or other things. The tool should help them understand.
