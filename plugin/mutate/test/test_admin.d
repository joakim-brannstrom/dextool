/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Niklas Pettersson (nikpe353@student.liu.se)
*/
module dextool_test.test_admin;

import std.conv : to;
import std.format : format;
import std.path : relativePath;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type : MutationId, Rationale;
import dextool.plugin.mutate.backend.type : Mutation;
static import dextool.type;

import dextool_test.utility;

alias Status = Mutation.Status;
alias Command = BuildCommandRunResult;
const errorOrFailure = ["error", "Failure"];

void commandNotFailed(Command cmd) {
    testAnyOrder!SubStr(errorOrFailure).shouldNotBeIn(cmd.stderr);
}

// dfmt off
@(testId ~ "shall mark a mutant without failing")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;
    auto id = MutationId(12);
    auto toStatus = Status.killed;
    auto rationale = `"A good rationale"`;

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(id)])
        .addArg(["--to-status", to!string(toStatus)])
        .addArg(["--rationale", rationale])
        .run;

    // assert
    commandNotFailed(r);
    testAnyOrder!SubStr([
        to!string(id),
        to!string(toStatus),
        rationale
    ]).shouldBeIn(r.stdout);
}

@(testId ~ "shall promt a failure message when marking a mutant that does not exist")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;
    auto db = createDatabase(testEnv);
    auto id = MutationId(5000);
    auto toStatus = Status.killed;
    auto rationale = `"This mutant should not exist"`;

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(id)])
        .addArg(["--to-status", to!string(toStatus)])
        .addArg(["--rationale", rationale])
        .run;

    // assert
    db.getMutation(id).isNull.shouldBeTrue;

    testAnyOrder!SubStr(errorOrFailure).shouldBeIn(r.stderr);
    testAnyOrder!SubStr([
        format!"Failure when marking mutant: %s"(to!string(id))
    ]).shouldBeIn(r.stderr);
}

@(testId ~ "shall mark same mutant twice")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;
    auto id = MutationId(3);
    auto wrongStatus = Status.killedByCompiler;
    auto wrongRationale = `"Backend claims mutant should not compile on target cpu"`;
    auto correctStatus = Status.unknown;
    auto correctRationale = `"Backend was wrong, mutant is legit..."`;

    // act
    auto firstRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(id)])
        .addArg(["--to-status", to!string(wrongStatus)])
        .addArg(["--rationale", wrongRationale])
        .run;
    auto secondRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(id)])
        .addArg(["--to-status", to!string(correctStatus)])
        .addArg(["--rationale", correctRationale])
        .run;

    // assert
    commandNotFailed(secondRes);
    testAnyOrder!SubStr([
        to!string(id),
        to!string(correctStatus),
        correctRationale
    ]).shouldBeIn(secondRes.stdout);
}

@(testId ~ "shall remove a marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;
    auto db = createDatabase(testEnv);
    auto id = MutationId(10);
    auto toStatus = Status.killed;
    auto rationale = `"This marking should not exist"`;

    // act
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(id)])
        .addArg(["--to-status", to!string(toStatus)])
        .addArg(["--rationale", rationale])
        .run;
    db.isMarked(id).shouldBeTrue;
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        to!string(id)])
        .run;

    // assert
    commandNotFailed(r);
    db.isMarked(id).shouldBeFalse;
    (db.getMutationStatus(id) == Status.unknown).shouldBeTrue;

    testAnyOrder!SubStr([
        format!"info: Removed marking for mutant %s"(to!string(id))
    ]).shouldBeIn(r.stdout);
}

@(testId ~ "shall fail to remove a marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;
    auto db = createDatabase(testEnv);
    auto id = MutationId(20);

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        to!string(id)])
        .run;

    // assert
    db.isMarked(id).shouldBeFalse;

    testAnyOrder!SubStr(errorOrFailure).shouldBeIn(r.stderr);
    testAnyOrder!SubStr([
        format!"Failure when removing marked mutant (mutant %s is not marked)"(to!string(id))
    ]).shouldBeIn(r.stderr);
}

@(testId ~ "shall notify lost marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv).addInputArg(testData ~ "fibonacci.cpp").run;
    auto id = MutationId(3);
    auto toStatus = Status.killedByCompiler;
    auto rationale = `"Lost"`;

    // act
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(id)])
        .addArg(["--to-status", to!string(toStatus)])
        .addArg(["--rationale", rationale])
        .run;
    auto r = makeDextoolAnalyze(testEnv).addInputArg(testData ~ "abs.cpp").run;

    // assert
    testAnyOrder!SubStr([
        "| ID | File                                              | Line | Column | Status           | Rationale |",
        "|----|---------------------------------------------------|------|--------|------------------|-----------|",
        "| 3  | build/plugin/mutate/plugin_testdata/fibonacci.cpp | 8    | 10     | killedByCompiler | \"Lost\"    |",
    ]).shouldBeIn(r.stdout);
}
