/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-plugin_mutate_mutation_ror
*/
module dextool_test.mutate_ror;

import dextool_test.utility;

import unit_threaded;

// dfmt off

@("shall produce all ROR mutations")
@Values("ror_primitive.cpp", "ror_overload.cpp")
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    makeDextool(testEnv)
        .addInputArg(testData ~ getValue!string)
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "ror"])
        .run;
    verifyRor(r.stdout);
}

void verifyRor(string[] txt) {
    import std.algorithm;

    static struct Ex {
        string[2] ops;
        string expr;
    }
    Ex[string] tbl = [
        "<": Ex(["<=", "!="], "false"),
        ">": Ex([">=", "!="], "false"),
        "<=": Ex(["<", "=="], "true"),
        ">=": Ex([">", "=="], "true"),
        "==": Ex(["<=", ">="], "false"),
        "!=": Ex(["<", ">"], "true"),
    ];

    foreach (mut; tbl.byKeyValue) {
        foreach (op; mut.value.ops) {
            auto expected = format("from '%s' to '%s'", mut.key, op);
            dextoolYap("Testing: " ~ expected);
            txt.sliceContains(expected).shouldBeTrue;
        }

        auto expected = format("from 'a %s b' to '%s'", mut.key, mut.value.expr);
        dextoolYap("Testing: " ~ expected);
        txt.sliceContains(expected).shouldBeTrue;
    }
}

@("shall produce all ROR mutations according to the alternative schema when both types are floating point types")
unittest {
    mixin(envSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "ror_float_primitive.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "ror"])
        .run;
    verifyFloatRor(r.stdout);
}

void verifyFloatRor(string[] txt) {
    import std.algorithm;

    static struct Ex {
        string[] ops;
        string expr;
    }
    Ex[string] tbl = [
        "<": Ex([">"], "false"),
        ">": Ex(["<"], "false"),
        "<=": Ex([">"], "true"),
        ">=": Ex(["<"], "true"),
        "==": Ex(["<=", ">="], "false"),
        "!=": Ex(["<", ">"], "true"),
    ];

    foreach (mut; tbl.byKeyValue) {
        foreach (op; mut.value.ops) {
            auto expected = format("from '%s' to '%s'", mut.key, op);
            dextoolYap("Testing: " ~ expected);
            txt.sliceContains(expected).shouldBeTrue;
        }

        auto expected = format("from 'a %s b' to '%s'", mut.key, mut.value.expr);
        dextoolYap("Testing: " ~ expected);
        txt.sliceContains(expected).shouldBeTrue;
    }
}

@("shall produce all ROR mutations according to the alternative schema when both types are enum type")
@ShouldFail
unittest {
    mixin(envSetup(globalTestdir));

    makeDextool(testEnv)
        .addInputArg(testData ~ "ror_enum_primitive.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["--mode", "test_mutants"])
        .addArg(["--mutant", "ror"])
        .run;
    verifyEnumRor(r.stdout);
}

void verifyEnumRor(string[] txt) {
    import std.algorithm;

    static struct Ex {
        string[] ops;
        string expr;
    }
    Ex[string] tbl = [
        "<": Ex([">"], "false"),
        ">": Ex(["<"], "false"),
        "<=": Ex([">"], "true"),
        ">=": Ex(["<"], "true"),
        "==": Ex(["<=", ">="], "false"),
        "!=": Ex(["<", ">"], "true"),
    ];

    foreach (mut; tbl.byKeyValue) {
        foreach (op; mut.value.ops) {
            auto expected = format("from '%s' to '%s'", mut.key, op);
            dextoolYap("Testing: " ~ expected);
            txt.sliceContains(expected).shouldBeTrue;
        }

        auto expected = format("from 'a %s b' to '%s'", mut.key, mut.value.expr);
        dextoolYap("Testing: " ~ expected);
        txt.sliceContains(expected).shouldBeTrue;
    }
}
