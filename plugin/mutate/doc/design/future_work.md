# REQ-future_work
partof: REQ-plugin_mutate
###
This is a meta requirement capturing future work and ideas to be performed in
the PoC.

# SPC-optimize_generated_mutants
partof: REQ-future_work
###
Implement the optimization found in [Improving Quality of Avionics Software Using Mutation Testing](http://liu.diva-portal.org/smash/record.jsf?pid=diva2%3A707336&dswid=-3612) to reduce the amount of equivalent mutants.

Use semantic information regarding the boundaries.

# SPC-visualization
partof: REQ-future_work
###
Implement interactive mutation visualisation.
See [triangle](http://john-tornblom.github.io/llvm-p86/triangle/) for an example.

The code used is at [wwwroot](https://github.com/john-tornblom/llvm-p86/tree/master/wwwroot).
The unminimized found at [shjs](http://shjs.sourceforge.net/).

To present the result a webserver is needed.
A first version can use the one from python stdlib.

For the syntax highlight to work correctly a tokenizer must be implemented.

Besides each file there should also be an _index_.

# SPC-multiple_mutations_at_mp
partof: REQ-future_work
###
This is a draft design for how to change the current mutations to be able to
generate _one_ source code that contains _all_ possible mutations for a
mutation point.

Wrap a C++ expression in a macro.
The macro delegates calls to an instance of a mutation point class.
Each instance of the mutation point class is uniquely identifiable via an ID.
Via the ID it is possible to control the mutation points:
 - activation
 - mutation operator

This makes it possible to NOT have to recompile the source code for each mutation.

Run all tests with the mutations inactivated.
This gives a list of all IDs in the code that are activated by the tests.
If any tests are failing put those IDs and tests on an ignore list.
Run the tests while activating mutation points at run-time via the IDs.

Possible extensions are to note the correlation between MP-ID and test-ID.
It would make it possible to run many tests in parallel and mutations if they
do NOT overlap.

The MP-ID should be generated in such a way that it can be mapped to an
external database containing all MP. Otherwise a command center can't make use
of the MP-ID.

A command center is expected to use the MP-ID to tell e.g. the mutation tester
to run the tests for the MP-ID.

## Idea

Maybe a simple way of doing this would be to generate a binary with *one* mutant for each mutation point. This would considerably reduce the number of compile cycles and should be relatively easy to implement.

# SPC-distributed_mutation
partof: REQ-future_work
###

## Step 1
Fix so many `test_mutants` components can run in parallel against the same underlying database.

The protocol for distribution can then be a simple `random selection`.
No timeout, queue or anything is needed. Just picking a random mutation to work with is enough.

What needs to be implemented is a switch to dictate the working directory.
The paths in the database then need to be relative to this working directory.
It is up to the user to make this _work_.

This can probably be done by slightly adjusting the --restrict flag.

## Step 2
Design a network protocol to facilitate network distributed workers.

The protocol shall be an open standard.
 * This is to facilitate integration with propitiatory modules.

Probably best to build upon vibe-d msgpack-rpc.

This is part of the _command_center_.
 * Implement the command_center that makes it possible to run multiple test_mutants.

## Step 3
I'm not sure this is needed or a good idea but I'm writing it down as a reminder.

Make it possible to implement specialized workers.
As is the current solution requires a worker being able to perform all the tasks.
But this prohibits integrating specialized works such as `equivalent mutation analyzers`/`build slaves`/`test slave`

To do this make a mutation go through a pipeline of states:
unknown
    -> passes compilation (1)
        -> mark as alive/dead by compiler
    -> test (2)
        -> fast analyzer for equivalent mutation
        -> build and run test suite
        -> mark as alive/dead/timeout
    -> post_test
        -> analyze for equivalent mutation (3)
1. a worker that check if the mutation passes the compiler. This will go fast. Can be done in memory.
2. The slowest is _probably_ to build and run the full test suite.
    A _fast_ symbolic execution could probably detect and eliminate some mutations.
    It could be an early filter.
3. This can be very time consuming.
    But even though it takes 10min per mutation it is still better than a human having to analyze by hand.

# SPC-notes_for_gui
partof: REQ-future_work
###

Consider using `vibe.d + CEF + vue.js` as the basis for a GUI.

# SPC-todo
partof: REQ-future_work
###
This is a simple TODO.
New items are added at the top

 * record the exit code when running tests. let segfaults not affect the timout test algorithm.
 * checksum all files under the test directory and save it together with a timestamp. Then we can show to the user how "out of sync" the tests are with the mutation report.
 * merge all schemas with only 1-2 mutants to "one" schema
 * present the first mutant that survived in a pull request as a diff. It should be "good enough" because the user is working on the pieace of code thus it should be able to "fast" understand what the mutant means.
 * because mutation testing is a specialization of fuzzy testing it should be possible to integrate similare techniques as is used in AFL such as the coverage instrumentation. The least we can do with this is getting the path coverage of a SUT. Could it also be used to "guide" us in what mutants to prioritize?
 * build a dependency for a file that is mutated such that it is only re-analyzed if that file or any of its dependencies has changed. Use the includeVisitor to find the dependencies.
 * show how the score is trending over time.
 * save changes to the mutation score in the database each time it has "finished" a run. It means that the user do not need external tooling to "plot" and visualize how the mutation score change over time.
 * add a database query that returns test cases sorted by the number of mutants they killed.
   change package.d to using it instead of sort_tcs_on_kills.
 * rank mutants by how much they changed the source code. more tokens then higher risk? Add to high interest mutants.
   an alternative would be how much they change the dataflow based on the LLVM IR.
 * allow the limits for the colors in the html report for files to be configurable.
    * The user may have either looser or stricter requirements than those that are hard coded atm.
 * save stdout/stderr log when testing mutants. this makes it easier to understand why "test" and "build" scripts fail.
 * make it possible for the user to define "mutation operator sets" from the 40+ primitives. There is no reason why they are hardcoded.
 * implement merge of databases. It is to make it possible for a team to work "distributed".
   For example make a copy of the database, make changes to the SUT and rerun the mutation testning.
   The take the result and "merge it back" into the teams shared database.
 * split the total time spent on mutation testing in: compile and execute tests
 * the time spent on mutations should always be added to the existing time, not overwritten.
 * UOI is probably wrong. It currently "only" insert unary operators. It do not change existing ops.
