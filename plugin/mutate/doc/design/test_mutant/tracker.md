# SPC-plugin_mutant_track_test_case
partof: REQ/SPC/TST-short text
###

TODO: add req.

## Design

The intention is to find test cases that *should* have killed mutants that survived and present those to the user. This makes it easier for the user to update a test suite to kill the mutant.

Let the program track what test cases fail (kill) what mutant. There will probably be multiple test cases for eachc mutant.
This creates a mapping between test cases and mutants.

I try to describe it in multiple ways to hopefully convey the message to the reader of this content:
 * By analyzing alive mutants with the surrounding mutation points it should be possible to find test cases to report to the user that *should* have killed the mutants.

## Musings

This is a *variant*, another approach, to using coverage.

This approach do not require that the target code can be compiled and executed with coverage.
This is *probably* information that the user would like either way.

A negative thing is that this would require the user to finish testing most of the mutants to get this information.
