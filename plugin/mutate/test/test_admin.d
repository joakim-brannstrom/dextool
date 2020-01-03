/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Niklas Pettersson (nikpe353@student.liu.se)
*/
module dextool_test.test_admin;

import std.conv : to;
import std.file : copy;
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
    testAnyOrder!SubStr(errorOrFailure).shouldNotBeIn(cmd.output);
}

// dfmt off
@(testId ~ "shall mark a mutant without failing")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).setWorkdir(workDir).addInputArg(dst).run;

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(MutationId(12))])
        .addArg(["--to-status", to!string(Status.killed)])
        .addArg(["--rationale", `"A good rationale"`])
        .run;

    // assert
    commandNotFailed(r);
    testAnyOrder!SubStr([
        to!string(MutationId(12)),
        to!string(Status.killed),
        `"A good rationale"`
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall promt a failure message when marking a mutant that does not exist")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).setWorkdir(workDir).addInputArg(dst).run;
    auto db = createDatabase(testEnv);

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(MutationId(5000))])
        .addArg(["--to-status", to!string(Status.killed)])
        .addArg(["--rationale", `"This mutant should not exist"`])
        .run;

    // assert
    db.getMutation(MutationId(5000)).isNull.shouldBeTrue;

    testAnyOrder!SubStr(errorOrFailure).shouldBeIn(r.output);
    testAnyOrder!SubStr([
        format!"Failure when marking mutant: %s"(to!string(MutationId(5000)))
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall mark same mutant twice")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).setWorkdir(workDir).addInputArg(dst).run;

    // act
    auto firstRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(MutationId(3))])
        .addArg(["--to-status", to!string(Status.killedByCompiler)])
        .addArg(["--rationale", `"Backend claims mutant should not compile on target cpu"`])
        .run;
    auto secondRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(MutationId(3))])
        .addArg(["--to-status", to!string(Status.unknown)])
        .addArg(["--rationale", `"Backend was wrong, mutant is legit..."`])
        .run;

    // assert
    commandNotFailed(secondRes);
    testAnyOrder!SubStr([
        to!string(MutationId(3)),
        to!string(Status.unknown),
        `"Backend was wrong, mutant is legit..."`
    ]).shouldBeIn(secondRes.output);
}

@(testId ~ "shall remove a marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).setWorkdir(workDir).addInputArg(dst).run;
    auto db = createDatabase(testEnv);

    // act
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(MutationId(10))])
        .addArg(["--to-status", to!string(Status.killed)])
        .addArg(["--rationale", `"This marking should not exist"`])
        .run;
    db.isMarked(MutationId(10)).shouldBeTrue;
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        to!string(MutationId(10))])
        .run;

    // assert
    commandNotFailed(r);
    db.isMarked(MutationId(10)).shouldBeFalse;
    (db.getMutationStatus(MutationId(10)) == Status.unknown).shouldBeTrue;

    testAnyOrder!SubStr([
        format!"info: Removed marking for mutant %s"(to!string(MutationId(10)))
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall fail to remove a marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).setWorkdir(workDir).addInputArg(dst).run;
    auto db = createDatabase(testEnv);

    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        to!string(MutationId(20))])
        .run;

    // assert
    db.isMarked(MutationId(20)).shouldBeFalse;

    testAnyOrder!SubStr(errorOrFailure).shouldBeIn(r.output);
    testAnyOrder!SubStr([
        format!"Failure when removing marked mutant (mutant %s is not marked)"(to!string(MutationId(20)))
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall notify lost marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).setWorkdir(workDir).addInputArg(dst).run;

    // act
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(MutationId(3))])
        .addArg(["--to-status", to!string(Status.killedByCompiler)])
        .addArg(["--rationale", `"Lost"`])
        .run;
    auto r = makeDextoolAnalyze(testEnv).addInputArg(testData ~ "abs.cpp").run;

    // assert
    testAnyOrder!SubStr([ // only check filename, not absolutepath (order is assumed in stdout)
        "| ID |", " File ", "    | Line | Column | Status           | Rationale |",
        "|----|", "--------------|------|--------|------------------|-----------|",
        "| 3  |", `fibonacci.cpp | 8    | 10     | killedByCompiler | "Lost"    |`,
    ]).shouldBeIn(r.output);
}
