# SPC-plugin_mutate_definitions
partof: REQ-plugin_mutate
done: by definition
###
Definitions for the mutate plugin.

## Assertions
(copied from the Artifact git repo)

Assertions **will** be used throughout the artifacts to mean:
- shall: the statement must be implemented and it's
    implementation verified.
- will: statement of fact, not subject to verification.
    I.e. "The X system will have timing as defined in ICD 1234"
- should: goals, non-mandatory provisions. Statements using "should"
    **should** be verified if possible, but verification is not mandatory if
    not possible. Is a statement of intent.

## License Documentation
(copied from the Artifact git repo)

All documentation for the mutate plugin including the Mutate Document
Specification and these design documents are both released under the CC0
Creative Commons Public Domain License. You can read more about CC0 here:
https://creativecommons.org/publicdomain/

## License Implementation
The implementation of the plugin is licensed under the MPL (Mozilla Public
License).

## License Test Cases
The test cases for the plugin are licensed under the Boost license.

## Risks
(copied from the Artifact git repo)
See [artifact security threat analysis](https://github.com/vitiral/artifact/blob/master/design/security.toml) for an example.

Risks are to be written with three sets of terms in mind:
- likelihood
- impact
- product placement

Likelihood has three categories:
 1. low
 2. medium
 3. high

Impact has five categories:
 1. sand
 2. pebble
 3. rock
 4. boulder
 5. avalanche

Product placement has three categories:
 1. cosmetic
 3. necessary
 5. critical

The value of these three categories will be multiplied to
determine the weight to assign to the risk.

> sand may seem small, but if you have enough sand in your
> gears, you aren't going anywhere.
>
> You definitely need to watch out for boulders and prevent
> avalanches whenever possible

## Document Language
Possible choices:
 - markdown: general purpose but lacks the tooling for a keeping the
   documentation cohesive.
 - doorstep: implemented in python which makes it harder than necessary to
   deploy.
 - artifact: implemented in rust which is a statically typed language that will
   lead to a reduction in production bugs. Statically linked binaries which
   make it easier to deploy.

The choice is artifact for writing the requirement documentation.

The reasons are:
 - tooling to help keep the tracing between design artifacts cohesive.
   This ruled out pure markdown.
 - a choice had to be made between doorstep and artifact. The feature set of
   them are in practice equivalent on a higher level.
   Artifact was chosen.
 - during the evaluation the tool has been extraordinarily stable.

## Programming Language
The mutation plugin **will** be written entirely in the D programming language
for the purpose of:
- cross compilation: D can be compiled on many platforms
- safety: SafeD catches memory safety bugs
- speed: D is as fast as C++
- static checking: the power of the static type checking in the language makes
  it easier to refactor the code
- scale-out: single threaded code can easily be made highly concurrent with the
  D standard library
- fun: D is a fun and productive language to write in.

Exception: For interoperability with the clang AST and LLVM backend certain
bridges may be developed in C++.

## DO-178C
Standard used in the avionics industry for developing software.

## Mutation Testing
Faults are injected into the SUT. Each such injection is a mutant.
Each mutant contains only one fault.
Test cases from the SUT are applied on the mutant.
The mutant is killed if the test suit fails.

## Test Case Adequacy
A test case is classified as adequate if it detects faults in the SUT.
A test case is shown to be adequate if it kills at least one mutant that generates an output that is different from the SUT.

## Mutation Testing Algorithm
Generate mutants.
Run test cases on the mutant.
 - if the test case *fail* the mutant is considered killed.

## Mutation Score
The mutation score of a test set T, designed to test P, is computed as:
MS(P, T) = Mk / (Mt - Mq)
Mk = mutants killed
Mq = equivalent mutants
Mt = total number of mutants

## Data Flow Score
DFS = Bu/Bt
Bu = Number of blocks (decision, p-uses, c-uses, all-uses) covered
Bt = Total number of feasable blocks

## SUT
System Under Test

## Mutation Point
A source code location that *can* be mutated.
A mutation point should contains what *kind* it is.
The kind can be what type of mutations it is applicable for, if it is an expression, statement etc.

The location should be a range and a [start, end) offset. The offset shall
completely cover the source code.

A mutation point has the status:
 - unknown
 - alive
 - dead

## Range notation
The notation [] and () have the same meaning as the mathematical symbols.
[] is the closed range, () is the open range.
An example is a c++ iterator. It has the range [), end is one beyond the last
element with a value in it.

## Mutant Testning
Mutation testing focus on determining the adequacy of a test cases.

It is a code-based testing technique.

It is _fault based testing_ directed towards _typical_ faults that occur when
constructing a program.

It relies on the competent programmer hypothesis which is the following
assumption [5]:
 - Given a specification a programmer develops a program that is either correct or differs from the correct program by a combination of simple errors

It also relies on “coupling effect” which suggests that [6]:
 - Test cases that detect simple types of faults are sensitive enough to detect more complex types of faults.

TODO check offuts book for the references [3] and [66].
The Competent Programmer Hypothesis (CPH) [3], [66] and the Coupling Effect [66].

See [1], page 3, chapter "The theory of mutation testing" for further
elaboration on the subject.

# TST-plugin_mutate_definitions
done: by definition
###
