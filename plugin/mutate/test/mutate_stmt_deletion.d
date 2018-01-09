/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
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
        .addArg(["--mutant", "stmtDel"])
        .run;
}

// #TST-plugin_mutate_statement_del_call_expression
@("shall delete function calls")
@ShouldFail("TODO fix stmtDel. is broken")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "stmt_deletion_of_call_expressions.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "stmtDel"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "'gun();' to ''",
        "'zen(2)' to ''",
        "'wun(zen(2));' to ''"
    ]).shouldBeIn(r.stdout);
}
