# Introduction

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

## Reading Instructions

A rudimentary tracing between requirements is done via markdown links and
heading prefixes. Its main purpose is to continuously document the important
use cases and design decisions that are made throughout the tool development.
It is to improve both the communication with those that aren't developers but
also to make it easier for outsides to understand what is important in the tool
and not when changing it.

Headings that start with one of the following prefixes indicate that they are
part of the requirement, design or test suite of the tool:

* REQ, requirement
* TST, test
* SPC, design

Tracing between them is done via markdown links.

# Development

A useful mutation tool must have *at least* the following characteristics:
 - easy to use in the day-to-day development.
 - performant _enough_ to give feedback early.
 - formal and robust _enough_ to pass a DO-178C tool qualification process for
   automation of required activities.
 - few false positives.

The development priorities to achieve the characteristics are broken down as
follows:

**Priority 1**: implement all interesting cases to get real world experience.
We do not know how to best use mutation testing in an industrial setting.
Instead of arguing and speculating what features are best when there are so
many low hanging fruits we instead choose to focus on implementing a broad
array of them to try them out in the real world. To get feedback from the users
in order to guide the future development.

This will of course need to be re-evaluated when the tool and process has
reached an acceptable maturity. This is further explained in the chapter
[PoC](#proof-of-concept).

**Priority 2**: add tests to show it continues working. The intention is to
continuously demonstrate progress to the stakeholders. An additional benefit is
a reduction of regressions which would greatly annoy our users.

**Priority 3**: maintain code quality standards. Reduce technical debt which
has a negative impact on development speed. This is in prepare the plugin for
being used outside of research projects.

## Proof Of Concept

The tool starts as a proof of concept that over time is converted to a
maintained, extendable tool.

The purpose of the PoC is to identify issues rather than solving them.

**Priority 1**: The PoC should realize enough features to act as a platform for
small scale mutation testing.

**Priority 2**: The PoC should be practical to use for source code mutation for
applications between 1k-10k SLOC.

The PoC thus help to derive and clarify the use cases.

 - what are the problems when scaling mutation testing?
 - what are the important usability characteristics needed by a mutation tool for every day development?
 - what mutations are important from a DO-178C perspective?
 - explore Offutt's and others idea for a scalable architecture for mutation testing.
 - explore the use cases at a small scale. What is missed? What are the future road blocks?

The PoC will focus on realizing the following features:

 - a minimal, viable set of mutation kinds derived from research papers.
 - for the first stage the PoC will not handle the problem of equivalent mutants.
    The PoC will be extended into this focus area in the future but first a MVP must be developed.
 - small scale architecture for continues and incremental mutation testing of an application.
 - ease of use.
 - the only language supported are C and c++.

# Architecture

TODO: add and write about the overall architecture regarding
analyze/test/report.

## Analyze

TODO

## Test

The test modules purpose is to go through all mutants with the status `unknown`
and classify them.

The top state machine for this is:

![The test drivers FSM](figures/test_mutant_fsm)

## Report

TODO

## Database Schema

The table `schema_version` should always be checked before any data is read.
Dextool will automatically update a database to the latest schema version
before reading from the database. In most cases this should be "ok" but some
updates of the schema are destructive which mean that data may be lost.

![Database schema](figures/database_schema)

### Mutation Schemata

A schemata consist of an unique ID and a number of fragments. A fragment is a
modification to a file (add/remove/replace). The order that the fragments are
applied is important and part of the fragment specification.

The analyze phase populates the database with schematas.

The test phase start by going through the `schemata_worklist` table to test all
the schematas that is in it. A schemata is removed from the worklist when it
has been tested.  This goes on until all schematas has been tested and their
results stored in the database.
