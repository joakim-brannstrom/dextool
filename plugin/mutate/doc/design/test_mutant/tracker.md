# SPC-plugin_mutant_track_test_case
partof: REQ/SPC/TST-short text
###

The program shall activate the *test case tracker* functionality when the *CLI* is *test case analyzer command*.

Requirements are active when *test case tracker.
 * The program shall associate the output from executing the *user supplied test case tracker* to the killed mutant when a mutant is killed.
 * The program shall as arguments to *user supplied test case tracker* use *stdout.log* and *stderr.log* when executing the *user supplied test case tracker*.

**Note**: *stdout.log* and *stderr.log* are in the current implementation files but it could be changed in the future.

The program shall cleanup the temporary directory containing *stdout.log* and *stderr.log* when a mutant test is finalized.

## Design

The intention is to find test cases that *should* have killed mutants that survived and present those to the user. This makes it easier for the user to update a test suite to kill the mutant.

Let the program track what test cases kill what mutant. There will probably be multiple test cases for each mutant. This creates a mapping between test cases and mutants.

This information about what test cases killed what mutant can then be used as suggestions to the user for what test cases that can be updated to kill alive mutants.

A simple way of doing this is to just report all test cases associate with a mutation point.

## Musings

This is a *variant*, another approach, to using coverage.

This approach do not require that the target code can be compiled and executed with coverage.
This is *probably* information that the user would like either way.

A negative thing is that this would require the user to finish testing most of the mutants to get this information.
