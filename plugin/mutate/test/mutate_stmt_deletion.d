/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

// #TST-plugin_mutate_statement_del_call_expression
*/
module dextool_test.mutate_stmt_deletion;

import dextool_test.utility;

// dfmt off

@("shall successfully run the ABS mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "statement_deletion.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "sdl"])
        .run;
}

@("shall delete function calls")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "sdl_func_call.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "sdl"])
        .run;

    testAnyOrder!SubStr([
        "'gun()' to '/*gun()*/'",
        "'wun(5)' to '/*wun(5)*/'",
        "'calc(6)' to '/*calc(6)*/'",
        "'wun(calc(6))' to '/*wun(calc(6))*/'",
        "'calc(7)' to '/*calc(7)*/'",
        "'calc(8)' to '/*calc(8)*/'",
        "'calc(10)' to '/*calc(10)*/'",
        "'calc(11)' to '/*calc(11)*/'",
    ]).shouldBeIn(r.stdout);
}
