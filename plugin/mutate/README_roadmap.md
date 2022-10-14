# Roadmap

The development of dextool mutate is focused on implementing a mutation testing
tool which just works. The use cases can be found [here](#req-use_cases).

The focus of this plugin is to enable a user to use mutation testing as an
assistant reviewer of test cases in order to improve the quality of the manual
review performed by a human. By automatically finding flaws in the tests and
improvement suggestions the reviewer can take this information together with
the domain specific knowledge to directly, pointedly suggest how the test suite
can be improved. This support of the review process of a test suite is intended
for both a partial (pull request) and full (the whole test suite) review.

* @mutationSurvey pp. 1-12;
* @mutationAnalysis chap. 2
* @mutationAnalysis [p. 20-24]

All features that are developed should make the focus easier to perform. Such
as by making the tool faster, preprocess and present information in an easier
format, simplify tool integration etc. Empower the developer, team and project
manager by guiding them where the test suite needs to improve and why. All
features should lead to a long term cost reduction when a project choose to use
mutation testing.

# Architectural Vision

The vision that the design should strive for is an architecture that enables
functional components to be added and replaced. Assume that the future is
undecided for how to best employ mutation testing thus it need to be easy to
modify the tool to suite the needs. The user features should, when implemented,
adhere to the architectural vision. The architectural vision is what makes it
possible to continue to develop the tool without degrading into an
unmaintainable mass of code.

Architectural goals:

 * it should be *expandable* with new modules without affecting existing modules
 * it should be possible to parallelize computationally heavy steps
 * the architecture should not limit the programing languages that can be
   mutation tested. It should be possible to use the architecture for mutation
   testing of any programming language
 * enable reuse of components. A visualization component should be reusable
   independent of the programming language that is mutation tested
 * it should be possible to incrementally use mutation testing during
   development
 * it should be robust to infrastructure failures

# Development Arcs

These are arcs that bundle goals into releases. An arc try to define a focus
for the next release together with mapping the items to implement.

## Arc Current

The focus is on usability. Improve the HTML report, make it easier to read and
faster to act on important information.

### Tasks

 * present the first mutant that survived in a pull request as a diff. It
   should be "good enough" because the user is working on the pieace of code
   thus it should be able to "fast" understand what the mutant means.
 * save the function name in the database for a coverage region.
 * add function metric to present to user a under-tested function. It is
   basically a mutation score per function.

## Arc Next

# TODO

A list of items that may or may not be done. It is both a collection of ideas
and actionable items. Irregardless of their nature they should all be in sync
with the vision of the tool. A simple item may exist in just this list while a
more complex may need to be broken down and added to the roadmap.

New items are added at the top

 * investigate testing of oldest mutant. somethings seems to be wrong when they are picked.
 * implement a function mutation coverage metric or something. It can be argued
   that mutation score is somewhat "meeh" as a metric. hard to use. But hardly
   anyone can argue that a function that is executed but no mutant is killed in
   it is "good". At least one of the mutants should have been killed. In other
   words, a function that is executed but totally untested is unarguably a sign
   of a deficiency of the test suite.
 * add an option to rank mutants by how much they change the code coverage (test impact).
    * computationally expensive so maybe add first after the static approaches
      are implemented such as AST affection.
 * rank mutants by how much they changed the source code. more tokens then
   higher risk? Add to high interest mutants.  an alternative would be how much
   they change the dataflow based on the LLVM IR.
 * document the coverage map and how to integrate with it such that a custom
   format can be integrated. This is to make it possible to e.g. use the
   coverage information from a [lauterbach probe](https://www.lauterbach.com/frames.html?home.html).
 * integrate coverage with embedded systems.
    * one way is to make it possible for a user to write to create a coverage
      map themself. this could be by e.g. exporting a json of what each byte
      represent.
    * another way is to import a plain json as coverage data. then the user can
      transform from whatever they want to this json and dextool imports it.
 * add an option to let the compilation flags be part of the checksum.
 * embed the configuration in the database to make it easier to share, review
   and archive. "how was the mutation testing tool actually executed?".
 * make it possible for the user to define "mutation operator sets" from the
   40+ primitives. There is no reason why they are hardcoded.
 * implement merge of databases. It is to make it possible for a team to work "distributed".
   For example make a copy of the database, make changes to the SUT and rerun the mutation testning.
   The take the result and "merge it back" into the teams shared database.
 * the time spent on mutations should always be added to the existing time, not overwritten.
 * Implement the optimization found in [Improving Quality of Avionics Software
   Using Mutation
   Testing](http://liu.diva-portal.org/smash/record.jsf?pid=diva2%3A707336&dswid=-3612)
   to reduce the amount of equivalent mutants.
 * the html report have an off-by-one error when displaying mutants.
