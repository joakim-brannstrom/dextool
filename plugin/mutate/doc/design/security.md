# SPC-file_security
partof: REQ-plugin_mutate
###

## General Filesystem Restrictions
In order to prevent the accidental delivery of a file with an injected fault.

Filesystem output *shall* be restricted to a _output directory_ provided by the user.

## Risks
There is a *high chance* of a coding error which lead to files being
overwritten on the filesystem which would cause an *avalanche risk* for the
state of the program or operating system.

In essence it could lead to a fatal bug being delivered to the customer.

The impact is dependent on a couple of compounding facts that escalate the problem.
Assumption:
 1. the user of the software has adequate version handling of the source code.
 2. the user of the version handling software are lazy and commit any modification to the source code without checking what it is.
 3. the user run the mutation testing on as a super user (able to modify operating system files).
 4. the user have an inadequate test suite that do not catch the mutations done to the original files before delivery to the customer.
 5. the user do not have any type of source code version handling.

TODO need further reasoning regarding the impacts. Lost production? Lost developer time?

Highest impact :
 - injection of a fault in production code that is not cought by the user.
   The production code with the injected fault is released to the customer.
   (assumptions 1,2,4 or 4,5)
 - injection of a fault in an operating system header.
   (assumption 3)

# SPC-file_security-single_output
partof: SPC-file_security
###
The plugin shall use the _current working directory_ as the _output directory_ by default.

The path to the database shall be retrieved from a class owned by the frontend.
The path shall be _rooted_ in the user supplied output directory.

## Design Restrictions
_note: the intention is to make it easier to review the software that it fulfills the requirement_

There *shall* be only one class that create and write generic files to the filesystem.

# SPC-file_security-header_as_warning
partof: SPC-file_security
###
The plugin shall write a line at the end of the mutated file to indicate that it has been mutated.
*Rationale: minor help for users with an adequate source code version system, major help for users without one.*
*Rationale: by writing to the end of the file it doesn't affect the generated reports so much*

# SPC-memory_safety
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
