/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

// #TST-statement_del_call_expression
*/
module dextool_test.mutate_stmt_deletion;

import dextool_test.utility;
import dextool_test.fixtures;

@(testId ~ "shall delete the body of functions returning void")
class ShallDeleteBodyOfFuncsReturningVoid : MutantFixture {
    override string programFile() {
        return "sdl_func_body_del.cpp";
    }

    override string op() {
        return "sdl";
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        auto r = precondition(testEnv);
        testAnyOrder!SubStr([`from ' f1Global = 2.2; ' to '/* f1Global = 2.2; */'`,
                `from ' z = 1.2; ' to '/* z = 1.2; */'`,
                `from ' method1 = 2.2; ' to '/* method1 = 2.2; */'`]).shouldBeIn(r.stdout);

        testAnyOrder!SubStr([`from ' return static_cast<int>(w);`, `from ' return method2`]).shouldNotBeIn(
                r.stdout);
    }
}

// dfmt off

@(testId ~ "shall successfully run the ABS mutator (no validation of the result)")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "statement_deletion.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "sdl"])
        .run;
}

@(testId ~ "shall delete function calls")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "sdl_func_call.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
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
