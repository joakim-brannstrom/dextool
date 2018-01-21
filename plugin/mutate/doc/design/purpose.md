# REQ-plugin_mutate
The purpose of this plugin is to perform mutation testing of a _target_.

The focus of this plugin is to use mutation testing to automate whole or part of the manual inspection of test procedures that are required when developing software to DAL-A and C according to RTCA-178C.

[@mutationSurvey pp. 1-12; also @mutationAnalysis chap. 2]

@mutationAnalysis [p. 20-24] also says.

A useful mutation tool must have *at least* the following characteristics:
- easy to use in the day-to-day development.
- performant _enough_ to give feedback early.
- formal and robust _enough_ to pass a DO-178C tool qualification process for automation of required activities.
- **TODO** add more desired characteristics.

These features will empower the developer to improve the quality of the test suite.
The features will lead to a long term cost reduction for a project using the tool.

The application requirements are split into the following categories:
- [[REQ-plugin_mutate-use_case]]
- [[REQ-plugin_mutate-derived]]
- [[REQ-plugin_mutate-development_process]]

# REQ-plugin_mutate-derived
This is a meta requirement for those that are derived from the implementation of the plugin.

These are not directly traceable to [[REQ-plugin_mutate-use_case]].

# REQ-plugin_mutate-development_process
Non-functional requirement on the development process of the plugin.

Priority 1: implement all interesting cases, get real code running.
Rational: the intention is to guide the design and implementation in a direction that will reach the end goal by finding flaws early.

Priority 2: add tests to show it continues working.
Rational: the intention is to continuesly demonstrate progress to the stakeholders. An additional benefit is a reduction of regressions.

Priority 3: maintain code quality standards.
Rational: reduce technical debt which has a negative impact on development speed.
Prepare the plugin for being used outside of research projects.

# SPC-plugin_mutate_poc_purpose
partof: REQ-plugin_mutate
done: by definition
###

The purpose of the PoC is to identify issues rather than solving them.

The PoC should realize enough features to act as a platform for small scale mutation testing.
The PoC should be practical to use for source code mutation for applications between 1k-10k SLOC.

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
