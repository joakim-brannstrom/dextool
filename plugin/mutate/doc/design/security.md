# SPC-plugin_mutate_file_security
partof: REQ-plugin_mutate
###
Document how it is of at must importance that the files being written to the
filesystem do not inadvertently trash the users files.

# SPC-plugin_mutate_memory_safety
partof: REQ-plugin_mutate
###

## General Security Feature
Note: This has to be re-evaluated if any network interfaces are added.

In order to prevent malicious input and reduce long term technical debt
resulting from memory safety bugs the plugin **shall** be developed in SafeD.

All functions and methods shall follow these criteria:
- **shall** be tagged with the @safe attribute. Either directly or inferred.
- uses of the @trusted attribute **shall** have a note explaining why this
  is needed and why it is deemed memory safe. The memory safety aspect shall
  cover all possible inputs.

## Risks
There is a *high chance* of a coding error which lead to a memory safety bug
which would cause an *avalanche risk* for the integrity of the program state.

It is not possible to make a definite statement regarding the impact on
security but the common wisdom is that memory safety bugs lead to security
compromises.

In essence it could lead to a full security compromise of the plugin.

Lowest impact:
- the program segfaults and thus become unusable.
- finding and fixing the bug is easy because the segfault lead to a usable
  stacktrace.

Medium impact:
- the memory safety problem manifest as a multithreading bug which is hard to
  track down and fix.

Highest impact:
- malicious input lead to a full security compromise of the user running the
  plugin.
