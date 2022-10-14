/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Niklas Pettersson (nikpe353@student.liu.se)
*/
module dextool_test.test_admin;

import core.time : dur, Duration;
import std.conv : to;
import std.file : copy;
import std.format : format;
import std.path : relativePath;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type : MutationStatusId, Rationale;
import dextool.plugin.mutate.backend.type : Mutation, ExitStatus, MutantTimeProfile;
static import dextool.type;

import dextool_test.fixtures;
import dextool_test.utility;

alias Status = Mutation.Status;
alias Command = BuildCommandRunResult;

class ShallResetMutantsThatATestCaseKilled : SimpleAnalyzeFixture {
    override string programFile() {
        return (testData ~ "report_one_ror_mutation_point.cpp").toString;
    }

    override void test() {
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        const mutants = db.mutantApi.getAllMutationStatus;
        mutants.length.shouldBeGreaterThan(4);

        // Arrange
        const tc1 = TestCase("tc_1");
        const tc2 = TestCase("tc_2");
        const tc3 = TestCase("tc_3");
        // tc1: [1,3,8,12,15]
        // tc2: [1,8,12,15]
        // tc3: [1,12]
        db.mutantApi.update(mutants[0], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.mutantApi.update(mutants[1], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
        db.mutantApi.update(mutants[2], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.mutantApi.update(mutants[3], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.mutantApi.update(mutants[4], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);

        db.testCaseApi.getTestCaseInfo(tc1).get.killedMutants.shouldBeGreaterThan(1);

        auto r = makeDextoolAdmin(testEnv).addArg([
            "--operation", "resetTestCase"
        ]).addArg(["--test-case-regex", `.*_1`]).run;

        db.testCaseApi.getTestCaseInfo(tc1).get.killedMutants.shouldEqual(0);
    }
}

class ShallRemoveTestCase : SimpleAnalyzeFixture {
    override string programFile() {
        return (testData ~ "report_one_ror_mutation_point.cpp").toString;
    }

    override void test() {
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        const mutants = db.mutantApi.getAllMutationStatus;
        mutants.length.shouldBeGreaterThan(4);

        // Arrange
        const tc1 = TestCase("tc_1");
        const tc2 = TestCase("tc_2");
        // tc1: [1,3,8,12,15]
        // tc2: [1,8,12,15]
        db.mutantApi.update(mutants[0], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        db.testCaseApi.updateMutationTestCases(mutants[0], [tc1, tc2]);
        db.mutantApi.update(mutants[1], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        db.testCaseApi.updateMutationTestCases(mutants[1], [tc1]);
        db.mutantApi.update(mutants[2], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        db.testCaseApi.updateMutationTestCases(mutants[2], [tc1, tc2]);
        db.mutantApi.update(mutants[3], Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        db.testCaseApi.updateMutationTestCases(mutants[3], [tc1, tc2]);

        db.testCaseApi.getTestCaseInfo(tc1).get.killedMutants.shouldBeGreaterThan(1);

        auto r = makeDextoolAdmin(testEnv).addArg([
            "--operation", "removeTestCase"
        ]).addArg(["--test-case-regex", `.*_1`]).run;

        db.testCaseApi.getTestCaseInfo(tc1).isNull.shouldBeTrue;
    }
}

@(testId ~ "shall mark a mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "mark_sdl_mutant.cpp";
    copy((testData ~ "mark_sdl_mutant.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    auto db = openDatabase(testEnv);
    const mutants = db.mutantApi.getAllMutationStatus;

    // dfmt off
    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        mutants[0].to!string])
        .addArg(["--to-status", to!string(Status.killed)])
        .addArg(["--rationale", `"A good rationale"`])
        .run;

    auto report = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "all_mut"])
        .addArg(["--section", "marked_mutants"])
        .run;

    // assert
    testAnyOrder!SubStr(["error"]).shouldNotBeIn(r.output);

    testAnyOrder!SubStr([
        to!string(1),
        to!string(Status.killed),
        `"A good rationale"`
    ]).shouldBeIn(r.output);
    // dfmt on
}

@(testId ~ "shall prompt a failure message when marking a mutant that does not exist")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).addInputArg(dst).addPostArg(["--mutant", "all"]).run;

    // act
    // dfmt off
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        "1"])
        .addArg(["--to-status", "killed"])
        .addArg(["--rationale", `"This mutant should not exist"`])
        .throwOnExitStatus(false)
        .run;
    // dfmt on

    // assert
    r.success.shouldBeFalse;

    auto db = openDatabase(testEnv);
    db.mutantApi.getMutation(MutationStatusId(1)).isNull.shouldBeTrue;

    testAnyOrder!SubStr(["error"]).shouldBeIn(r.output);
    testAnyOrder!SubStr([format!"Mutant with ID %s do not exist"(1)]).shouldBeIn(r.output);
}

@(testId ~ "shall mark same mutant twice")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    auto db = openDatabase(testEnv);
    const id = db.mutantApi.getAllMutationStatus[0].to!string;

    // act
    // dfmt off
    auto firstRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        id])
        .addArg(["--to-status", to!string(Status.killedByCompiler)])
        .addArg(["--rationale", `"Backend claims mutant should not compile on target cpu"`])
        .run;
    auto secondRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        id])
        .addArg(["--to-status", to!string(Status.unknown)])
        .addArg(["--rationale", `"Backend was wrong, mutant is legit..."`])
        .run;

    // assert
    testAnyOrder!SubStr(["error"]).shouldNotBeIn(secondRes.output);
    testAnyOrder!SubStr([
        id,
        to!string(Status.unknown),
        `"Backend was wrong, mutant is legit..."`
    ]).shouldBeIn(secondRes.output);
    // dfmt on
}

@(testId ~ "shall remove a marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    auto db = openDatabase(testEnv);
    const mutants = db.mutantApi.getAllMutationStatus;
    const id = mutants[0].to!string;

    // act
    // dfmt off
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        id])
        .addArg(["--to-status", to!string(Status.killed)])
        .addArg(["--rationale", `"This marking should not exist"`])
        .run;
    db.markMutantApi.isMarked(mutants[0]).shouldBeTrue;

    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        id])
        .run;
    // dfmt on

    // assert
    testAnyOrder!SubStr(["error"]).shouldNotBeIn(r.output);
    db.markMutantApi.isMarked(mutants[0]).shouldBeFalse;
    (db.mutantApi.getMutationStatus(mutants[0]) == Status.unknown).shouldBeTrue;

    testAnyOrder!SubStr([format!"info: Removed marking for mutant %s"(id)]).shouldBeIn(r.output);
}

@(testId ~ "shall fail to remove a marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;
    auto db = openDatabase(testEnv);

    // act
    // dfmt off
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        "20"])
        .run;
    // dfmt on

    // assert
    db.markMutantApi.isMarked(MutationStatusId(20)).shouldBeFalse;

    testAnyOrder!SubStr(["error"]).shouldBeIn(r.output);
    testAnyOrder!SubStr([
        "Failure when removing marked mutant (mutant 20 is not marked"
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall notify lost marked mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);

    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    auto db = openDatabase(testEnv);
    const id = db.mutantApi.getAllMutationStatus[0].to!string;

    // act
    // dfmt off
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        id])
        .addArg(["--to-status", to!string(Status.killedByCompiler)])
        .addArg(["--rationale", `"Lost"`])
        .run;

    auto r = makeDextoolAnalyze(testEnv).addInputArg(testData ~ "abs.cpp")
        .addArg("--force-save").run;

    // assert
    testAnyOrder!Re([ // only check filename, not absolutepath (order is assumed in stdout)
        "| ID |", " File ", "    | Line | Column | Status           | Rationale |",
        format!"| %s  |"(id), `fibonacci.cpp |.*|.*|.*| "Lost"    |`,
    ]).shouldBeIn(r.output);
    // dfmt on
}

@("shall successfully execute the admin operation stopTimeoutTest")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAdmin(testEnv).addArg(["--operation", "stopTimeoutTest"]).run;
}

@("shall successfully execute the admin operation resetMutantSubKind")
unittest {
    mixin(EnvSetup(globalTestdir));

    makeDextoolAdmin(testEnv).addArg([
        "--operation", "resetMutantSubKind", "--mutant-sub-kind", "stmtDel"
    ]).run;
}
