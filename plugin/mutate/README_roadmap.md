# Roadmap

The development of dextool mutate is focused on implementing a mutation testing
tool which just works. The use cases can be found [here](#req-use_cases).

The vision that the design should strive for is an architecture that enables
functional components to freely added and replaced.

Assume that the future is uncertain.

Architectural goals:
 * it should be *expandable* with new modules without affecting existing modules
 * it should be possible to parallelize
 * the programming language a module is written in should be left as an
   implementation detail for the module
 * the architecture should not limit the programing languages that can be
   mutation tested. It should be possible to use the architecture for mutation
   testing of any programming language
 * enable reuse of components. A visualization component should be reusable
   independent of the programming language that is mutation tested
 * it should be possible to incrementally use mutation testing during development.
 * it should be robust to infrastructure failures

The purpose of this plugin is to perform mutation testing of a _target_.

The focus of this plugin is to use mutation testing to automate whole or part
of the manual inspection of test procedures that are required when developing
software to DAL-A and C according to RTCA-178C.

* @mutationSurvey pp. 1-12;
* @mutationAnalysis chap. 2
* @mutationAnalysis [p. 20-24]

These features will empower the developer to improve the quality of the test
suite. The features will lead to a long term cost reduction for a project using
the tool.

# TODO

A list of items that may or may not be done. It is both a collection of ideas
and actionable items. Irregardless of their nature they should all be in sync
with the vision of the tool. A simple item may exist in just this list while a
more complex may need to be broken down and added to the roadmap.

New items are added at the top

 * document the coverage map and how to integrate with it such that a custom
   format can be integrated. This is to make it possible to e.g. use the
   coverage information from a [lauterbach probe](https://www.lauterbach.com/frames.html?home.html).
 * move injecting of schemata header to runtime so it isn't stored in the
   database multiple times.
 * integrate coverage with embedded systems.
    * one way is to make it possible for a user to write to create a coverage
      map themself. this could be by e.g. exporting a json of what each byte
      represent.
    * another way is to import a plain json as coverage data. then the user can
      transform from whatever they want to this json and dextool imports it.
 * add an option to let the file path, relative, be part of the checksum.
 * add an option to let the compilation flags be part of the checksum.
 * embed the configuration in the database to make it easier to share, review
   and archive. "how was it actually tested".
 * use file checksum to NOT analyze redundant files. note though that this
   requires a dependency tree so headers are re-analyzed even though the root
   is unchanged.
 * add prioritization based on the size of a mutant with a cut-off like max(10,
   offset.end - offset.begin).
 * checksum all files under the test directory and save it together with a
   timestamp. Then we can show to the user how "out of sync" the tests are with
   the mutation report.
 * merge all schemas with only 1-2 mutants to "one" schema
 * present the first mutant that survived in a pull request as a diff. It
   should be "good enough" because the user is working on the pieace of code
   thus it should be able to "fast" understand what the mutant means.
 * because mutation testing is a specialization of fuzzy testing it should be
   possible to integrate similare techniques as is used in AFL such as the
   coverage instrumentation. The least we can do with this is getting the path
   coverage of a SUT. Could it also be used to "guide" us in what mutants to
   prioritize?
 * build a dependency for a file that is mutated such that it is only
   re-analyzed if that file or any of its dependencies has changed. Use the
   includeVisitor to find the dependencies.
 * add a database query that returns test cases sorted by the number of mutants they killed.
   change package.d to using it instead of `sort_tcs_on_kills`.
 * rank mutants by how much they changed the source code. more tokens then
   higher risk? Add to high interest mutants.  an alternative would be how much
   they change the dataflow based on the LLVM IR.
 * allow the limits for the colors in the html report for files to be configurable.
    * The user may have either looser or stricter requirements than those that
      are hard coded atm.
 * make it possible for the user to define "mutation operator sets" from the
   40+ primitives. There is no reason why they are hardcoded.
 * implement merge of databases. It is to make it possible for a team to work "distributed".
   For example make a copy of the database, make changes to the SUT and rerun the mutation testning.
   The take the result and "merge it back" into the teams shared database.
 * split the total time spent on mutation testing in: compile and execute tests
 * the time spent on mutations should always be added to the existing time, not overwritten.
 * UOI is probably wrong. It currently "only" insert unary operators. It do not change existing ops.
 * Implement the optimization found in [Improving Quality of Avionics Software Using Mutation Testing](http://liu.diva-portal.org/smash/record.jsf?pid=diva2%3A707336&dswid=-3612) to reduce the amount of equivalent mutants.
