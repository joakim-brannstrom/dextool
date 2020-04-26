/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-mutation_dcc
*/
module dextool_test.mutate_dcc;

import std.algorithm : joiner, count;

import dextool_test.fixtures;
import dextool_test.utility;

// dfmt off

@(testId ~ "shall produce 2 predicate mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcc_dc_ifstmt1.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcc"])
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
        .addInputArg(testData ~ "dcc_dc_ifstmt2.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcc"])
        .run;
    testAnyOrder!SubStr([
        "from 'x' to 'true'",
        "from 'x' to 'false'",
        "from 'y' to 'true'",
        "from 'y' to 'false'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 2 predicate mutations for an expression of multiple clauses")
@Values("dcc_dc_ifstmt3.cpp", "dcc_dc_stmt3.cpp")
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ getValue!string)
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcc"])
        .run;
    testAnyOrder!SubStr([
        "from 'x == 0 || y == 0' to 'true'",
        "from 'x == 0 || y == 0' to 'false'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 6 clause mutations")
@Values("dcc_cc_ifstmt1.cpp", "dcc_cc_stmt1.cpp")
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!string);
    testEnv.setupEnv;

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ getValue!string)
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcc"])
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

@(testId ~ "shall produce 4 switch bomb mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcc_dc_switch1.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcc"])
        .run;
    testAnyOrder!SubStr([
        "from 'return -1 ;' to '*((char*)0)='x';break;'",
        "from 'return 1;' to '*((char*)0)='x';break;'",
        "from 'break;' to '*((char*)0)='x';break;'",
        "from '' to '*((char*)0)='x';break;'",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 4 switch deletion mutations")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcc_dc_switch1.cpp")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testConsecutiveSparseOrder!SubStr([
        "from 'case 0:",
        "return -1 ;' to ''",

        "from 'case 1:",
        "return 1;' to ''",

        "from 'case 3:",
        "break;' to ''",

        "from 'case 4:' to ''",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall produce 1 DCC mutant in C when the input is a C file")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "dcc_as_c_file.c")
        .run;
    auto r = makeDextool(testEnv)
        .addArg(["test"])
        .addArg(["--mutant", "dcr"])
        .run;
    testConsecutiveSparseOrder!SubStr([
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

// shall produce 6 predicate and 8 clause mutations for an expression of
// multiple clauses of C code
class ShallProduceAllDccMutantsWithSchemataForC : SchemataFixutre {
    override string programFile() {
        return (testData ~ "dcc_dc_stmt4.c").toString;
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
            "from 'x == TRUE' to '1'",
            "from 'x == TRUE' to '0'",
            ];

        testAnyOrder!SubStr(expected).shouldBeIn(runDextoolTest(testEnv, ["--mutant", "dcc"]).output);
        makeDextoolAdmin(testEnv).addArg(["--operation", "resetMutant", "--status", "alive"]).run;
        testAnyOrder!SubStr(expected).shouldBeIn(makeDextool(testEnv).addArg(["test"]).addArg(["--mutant", "dcc"]).run.output);
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
        testAnyOrder!SubStr(["from 'argc == 1' to 'true'"]).shouldBeIn(runDextoolTest(testEnv, ["--mutant", "dcr"]).output);
    }
}
