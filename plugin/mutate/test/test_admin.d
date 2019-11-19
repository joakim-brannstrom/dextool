/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Niklas Pettersson (nikpe353@student.liu.se)
*/
module dextool_test.test_admin;

import std.path : relativePath;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;
static import dextool.type;

import dextool_test.utility;

string[] errorOrFailure = ["error", "Failure"];

// dfmt off
@(testId ~ "shall mark a mutant without failing")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id", "12"])
        .addArg(["--to-status", "killed"])
        .addArg(["--rationale", `"A good rationale"`])
        .run;

    // assert
    testAnyOrder!SubStr(errorOrFailure).shouldNotBeIn(r.stderr);
    testAnyOrder!SubStr([
        "12",
        "killed",
        `"A good rationale"`
    ]).shouldBeIn(r.stdout);
}

@(testId ~ "shall promt a failure message when marking a mutant that does not exist")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id", "5000"])
        .addArg(["--to-status", "killed"])
        .addArg(["--rationale", `"This mutant should not exist"`])
        .run;

    // assert
    testAnyOrder!SubStr(["Failure when marking mutant: 5000"]).shouldBeIn(r.stderr);
    testAnyOrder!SubStr(errorOrFailure).shouldBeIn(r.stderr);
}

@(testId ~ "shall mark same mutant twice")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;

    // act
    auto firstRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id", "3"])
        .addArg(["--to-status", "killedByCompiler"])
        .addArg(["--rationale", `"Backend claims mutant should not compile on target cpu"`])
        .run;
    auto secondRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id", "3"])
        .addArg(["--to-status", "unknown"])
        .addArg(["--rationale", `"Backend was wrong, mutant is legit..."`])
        .run;

    // assert
    testAnyOrder!SubStr(errorOrFailure).shouldNotBeIn(secondRes.stderr);
    testAnyOrder!SubStr([
        "3",
        "unknown",
        `"Backend was wrong, mutant is legit..."`
    ]).shouldBeIn(secondRes.stdout);
}

// TODO: add test for plain-report for marked mutants.
