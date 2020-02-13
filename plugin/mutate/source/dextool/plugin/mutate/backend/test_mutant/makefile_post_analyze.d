/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännströmoakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.makefile_post_analyze;

import std.exception : collectException;
import std.range : isInputRange, isOutputRange;
import logger = std.experimental.logger;

import dextool.plugin.mutate.backend.test_mutant.interface_ : TestCaseReport, GatherTestCase;
import dextool.plugin.mutate.backend.type : TestCase;
import dextool.type : AbsolutePath;

/** Parse input for the first makefile targets that fail.
 *
 * It is important that it is the first failing to avoid possible problems with
 * recursive makefiles which would end with multiple makefile targets that
 * fail. I assume that the first one is the most specific and relevant.
 *
 * TODO: if that isn't good enough maybe another approach would be to
 * concatenate them to one big target? It would reflect in a "chain" of targets
 * that lead up to the error.
 *
 * Params:
 *  r = range that is chunked by line
 *  report = where the results are put.
  */
struct MakefileParser {
    import std.regex : regex, matchFirst;

    private {
        bool isDone;

        // example: binary exiting with something else than zero.
        //make: *** [exit1] Error 1
        //make: *** [exit2] Error 2
        //make: *** [segfault] Segmentation fault (core dumped)
        enum re_exit_with_error_code = regex(`.*make:\s*\*\*\*\s*\[(?P<tc>.*)\].*`);
    }

    void process(T)(T line, TestCaseReport report) {
        import std.range : put;
        import std.string : strip;

        if (isDone)
            return;

        auto exit_with_error_code_match = matchFirst(line, re_exit_with_error_code);

        if (!exit_with_error_code_match.empty) {
            report.reportFailed(TestCase(exit_with_error_code_match["tc"].strip.idup));
            isDone = true;
        }
    }
}

version (unittest) {
    import std.algorithm : each;
    import std.array : array;
    import unit_threaded : shouldEqual, shouldBeIn;
}

@("shall report the failed test case")
unittest {
    auto app = new GatherTestCase;

    MakefileParser parser;
    // dfmt off
    foreach (a; [
    `./a.out segfault`,
    `segfault`,
    `makefile:4: recipe for target 'segfault' failed`,
    `make: *** [segfault] Segmentation fault (core dumped)`,
    `make: *** [exit1] Error 1`,
    `make: *** [exit2] Error 2`,
    ]) parser.process(a, app);
    // dfmt on

    shouldEqual(app.failed.byKey.array, [TestCase("segfault")]);
}
