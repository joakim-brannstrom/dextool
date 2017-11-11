# REQ-plugin_mutate
The purpose of this plugin is to perform mutation testing of a _target_.

The focus of this plugin is to use mutation testing to automate whole or part of the manual inspection of test procedures that are required when developing software to DAL-A and C according to RTCA-178C.

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

# REQ-plugin_mutate-use_case
This is a meta requirement for those that are traceable to use cases.

An important aspect is ease of use in day-to-day development. When verification is performed late in the development process, one discovers generally a huge amount of problems, and fixing them requires a tremendous effort; it is sometimes extremely difficult to do when the software has already gone through various validation phases that would be ruined by massive corrections. When the tool is integrated into the development environment, programmers must be able to run it routinely each time they develop new modules or modify existing ones, ideally as part of the code compile step. The sooner checking is performed in the development process, the better.
