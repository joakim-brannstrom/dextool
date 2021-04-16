/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.mutate_dcr;

import std.algorithm : joiner, count;

import dextool_test.fixtures;
import dextool_test.utility;

// dfmt off

@(testId ~ "shall produce 2 predicate mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcr_dc_ifstmt1.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testAnyOrder!SubStr([
        "from 'x' to 'true'",
        "from 'x' to 'false'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 4 predicate mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcr_cc_ifstmt_bug.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testAnyOrder!SubStr([
        "from '!otherFun()' to 'true'",
        "from '!otherFun()' to 'false'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 4 predicate mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcr_dc_ifstmt2.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testAnyOrder!SubStr([
        "from 'x' to 'true'",
        "from 'x' to 'false'",
        "from 'y' to 'true'",
        "from 'y' to 'false'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 2 predicate mutations for an expression of multiple clauses")
unittest {
    foreach (sourceFile; ["dcr_dc_stmt3.cpp", "dcr_dc_ifstmt3.cpp"]) {
        mixin(envSetup(globalTestdir, No.setupEnv));
        testEnv.outputSuffix(sourceFile);
        testEnv.setupEnv;

        makeDextoolAnalyze(testEnv)
            .addInputArg(testData ~ sourceFile)
            .run;
        auto r = makeDextool(testEnv)
            .addArg(["test"])
            .addArg(["--mutant", "dcr"])
            .run;
        testAnyOrder!SubStr([
            "from 'x == 0' to 'true'",
            "from 'x == 0' to 'false'",
            "from 'y == 0' to 'true'",
            "from 'y == 0' to 'false'",
            "from 'x == 0 || y == 0' to 'true'",
            "from 'x == 0 || y == 0' to 'false'",
        ]).shouldBeIn(r.output);
    }
}

@(testId ~ "shall produce 6 clause mutations")
unittest {
foreach (getValue; ["dcr_cc_ifstmt1.cpp", "dcr_cc_stmt1.cpp"]) {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue);
    testEnv.setupEnv;

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ getValue)
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testAnyOrder!SubStr([
        "from 'x == 0' to 'true'",
        "from 'x == 0' to 'false'",
        "from 'x == 1' to 'true'",
        "from 'x == 1' to 'false'",
        "from 'x == 2' to 'true'",
        "from 'x == 2' to 'false'",
        "from 'y > 0' to 'true'",
        "from 'y > 0' to 'false'",
        "from 'x > 2' to 'true'",
        "from 'x > 2' to 'false'",
    ]).shouldBeIn(r.output);

    r.output.joiner.count("'x == 0'").shouldEqual(2);
    r.output.joiner.count("'x == 1'").shouldEqual(2);
    r.output.joiner.count("'x == 2'").shouldEqual(2);
    r.output.joiner.count("'y > 0'").shouldEqual(2);
    r.output.joiner.count("'x > 2'").shouldEqual(2);
}
}

@(testId ~ "shall produce 5 mutations in the switch")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcr_dc_switch1.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testConsecutiveSparseOrder!SubStr([
        "from 'false' to 'true'",
        "from 'true' to 'false'",
        "from 'false' to 'true'",
        "from 'false' to 'true'",
        "from 'true' to 'false'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 1 DCR mutant in C when the input is a C file")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcr_as_c_file.c")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testAnyOrder!SubStr([
        "from 'x == 0' to '1'",
        "from 'x == 0' to '0'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 2 predicate mutants for the bool function")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcr_bool_func.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testAnyOrder!SubStr([
        "from 'fun(x)' to 'true'",
        "from 'fun(x)' to 'false'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall block DCR when the operand is a non-boolean")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcr_cc_ifstmt2.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testAnyOrder!SubStr([
        "from 'x' to 'true'",
        "from 'x' to 'false'",
        "from 'y' to 'true'",
        "from 'y' to 'false'",
    ]).shouldNotBeIn(r.output);
}

// shall produce 6 predicate and 8 clause mutations for an expression of
// multiple clauses of C code
class ShallProduceAllDcrMutantsWithSchemataForC : SchemataFixutre {
    override string programFile() {
        return (testData ~ "dcr_dc_stmt4.c").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        programCode = "program.c";
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto expected = [
            // isIfStmt
            "from 'x == 0 || y == 0' to '1'",
            "from 'x == 0 || y == 0' to '0'",
            "from 'x == 0' to '1'",
            "from 'x == 0' to '0'",
            "from 'y == 0' to '1'",
            "from 'y == 0' to '0'",
            // isPredicateFunc
            "from 'x == 0 || y == 0' to '1'",
            "from 'x == 0 || y == 0' to '0'",
            "from 'x == 0' to '1'",
            "from 'x == 0' to '0'",
            "from 'y == 0' to '1'",
            "from 'y == 0' to '0'",
            // isPredicateFunc2
            "from 'x == 0 || y == 0' to '1'",
            "from 'x == 0 || y == 0' to '0'",
            "from 'x == 0' to '1'",
            "from 'x == 0' to '0'",
            "from 'y == 0' to '1'",
            "from 'y == 0' to '0'",
            // isPredicateFunc3
            // not possible because of C macros
            "from 'x == TRUE' to '1'",
            "from 'x == TRUE' to '0'",
            ];

        auto r0 = runDextoolTest(testEnv).addPostArg(["--mutant", "dcr"]).run;
        testAnyOrder!SubStr(expected).shouldBeIn(r0.output);
        testAnyOrder!SubStr(["error:"]).shouldNotBeIn(r0.output);

        makeDextoolAdmin(testEnv).addArg(["--operation", "resetMutant", "--status", "alive"]).run;
        testAnyOrder!SubStr(expected).shouldBeIn(makeDextool(testEnv).addArg(["test"]).addArg(["--mutant", "dcr"]).run.output);

    }
}

class ShallSkipDcrMutantInsideTemplate : SchemataFixutre {
    override string programFile() {
        return (testData ~ "dcr_inside_template_param.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        // this mean that the schemata has to be able to compile and run with
        // this mutant
        // TODO: add this to expected. from 'x == 1' to 'true'
        // but for now removing it because it seems to fail on min docker
        // image. Probably something to do with the compiler.
        testAnyOrder!SubStr(["error:"]).shouldNotBeIn(runDextoolTest(testEnv).addPostArg(["--mutant", "dcr"]).run.output);
    }
}

class ShallGenerateValidDcrForOnelineIfSchema : SchemataFixutre {
    override string programFile() {
        return (testData ~ "dcr_cc_ifstmt2.cpp").toString;
    }

    override void test() {
        import std.file : readText;
        import std.json;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv)
            .addInputArg(programCode)
            .addPostArg(["--schema-min-mutants", "0"])
            .addFlag("-std=c++11")
            .run;

        runDextoolTest(testEnv)
            .addPostArg(["--mutant", "dcr"])
            .addFlag("-std=c++11")
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString))["stat"];
        j["alive"].integer.shouldBeGreaterThan(12);
        j["killed"].integer.shouldEqual(0);
    }
}

class ShallGenerateValidDcrForDeclIfSchema : SchemataFixutre {
    override string programFile() {
        return (testData ~ "dcr_cc_ifstmt3.cpp").toString;
    }

    override void test() {
        import std.file : readText;
        import std.json;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addFlag("-std=c++11").run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "dcr"]).addFlag("-std=c++11").run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        testAnyOrder!SubStr([
            "from 'Foo::a < Bar::a' to 'true'",
            "from 'Foo::a < Bar::a' to 'false'",
            "from 'argc == 5 || argc == 7' to 'true'",
            "from 'argc == 5 || argc == 7' to 'false'",
            "from 'argc == 42 || argc == 3' to 'true'",
            "from 'argc == 42 || argc == 3' to 'false'",
        ]).shouldBeIn(r.output);

        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString))["stat"];
        j["alive"].integer.shouldBeGreaterThan(5);
        j["killed"].integer.shouldBeGreaterThan(5);
    }
}
