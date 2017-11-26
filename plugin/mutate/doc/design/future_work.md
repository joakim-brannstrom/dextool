# REQ-plugin_mutate_future_work
partof: REQ-plugin_mutate
###
This is a meta requirement capturing future work and ideas to be performed in
the PoC.

# SPC-plugin_mutate_optimize_generated_mutants
partof: REQ-plugin_mutate_future_work
###
Implement the optimization found in [Improving Quality of Avionics Software Using Mutation Testing](http://liu.diva-portal.org/smash/record.jsf?pid=diva2%3A707336&dswid=-3612) to reduce the amount of equivalent mutants.

# SPC-plugin_mutate_visualization
partof: REQ-plugin_mutate_future_work
###
Implement interactive mutation visualisation.
See [triangle](http://john-tornblom.github.io/llvm-p86/triangle/) for an example.

The code used is at [wwwroot](https://github.com/john-tornblom/llvm-p86/tree/master/wwwroot).
The unminimized found at [shjs](http://shjs.sourceforge.net/).

# SPC-plugin_mutate_multiple_mutations_at_mp
partof: REQ-plugin_mutate_future_work
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
