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
import std.traits : EnumMembers;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type : MutationId, Rationale;
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
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        import dextool.plugin.mutate.backend.type : TestCase;

        // Arrange
        const tc1 = TestCase("tc_1");
        const tc2 = TestCase("tc_2");
        const tc3 = TestCase("tc_3");
        // tc1: [1,3,8,12,15]
        // tc2: [1,8,12,15]
        // tc3: [1,12]
        db.updateMutation(MutationId(1), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.updateMutation(MutationId(2), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
        db.updateMutation(MutationId(3), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.updateMutation(MutationId(4), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.updateMutation(MutationId(5), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);

        db.getTestCaseInfo(tc1, [EnumMembers!(Mutation.Kind)])
            .get.killedMutants.shouldBeGreaterThan(1);

        auto r = makeDextoolAdmin(testEnv).addArg([
                "--operation", "resetTestCase"
                ]).addArg(["--test-case-regex", `.*_1`]).run;

        db.getTestCaseInfo(tc1, [EnumMembers!(Mutation.Kind)]).get.killedMutants.shouldEqual(0);
    }
}

class ShallRemoveTestCase : SimpleAnalyzeFixture {
    override string programFile() {
        return (testData ~ "report_one_ror_mutation_point.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        import dextool.plugin.mutate.backend.type : TestCase;

        // Arrange
        const tc1 = TestCase("tc_1");
        const tc2 = TestCase("tc_2");
        // tc1: [1,3,8,12,15]
        // tc2: [1,8,12,15]
        db.updateMutation(MutationId(1), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.updateMutation(MutationId(2), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
        db.updateMutation(MutationId(3), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.updateMutation(MutationId(4), Mutation.Status.killed, ExitStatus(0),
                MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);

        db.getTestCaseInfo(tc1, [EnumMembers!(Mutation.Kind)])
            .get.killedMutants.shouldBeGreaterThan(1);

        auto r = makeDextoolAdmin(testEnv).addArg([
                "--operation", "removeTestCase"
                ]).addArg(["--test-case-regex", `.*_1`]).run;

        db.getTestCaseInfo(tc1, [EnumMembers!(Mutation.Kind)]).get.killedMutants.shouldEqual(0);
    }
}

@(testId ~ "shall mark a mutant")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "mark_sdl_mutant.cpp";
    copy((testData ~ "mark_sdl_mutant.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    // dfmt off
    // act
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(1)])
        .addArg(["--to-status", to!string(Status.killed)])
        .addArg(["--rationale", `"A good rationale"`])
        .run;

    auto report = makeDextoolReport(testEnv, testData.dirName)
        .addPostArg(["--mutant", "all"])
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
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    // act
    // dfmt off
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        "5000"])
        .addArg(["--to-status", "killed"])
        .addArg(["--rationale", `"This mutant should not exist"`])
        .throwOnExitStatus(false)
        .run;
    // dfmt on

    // assert
    r.success.shouldBeFalse;

    auto db = createDatabase(testEnv);
    db.getMutation(MutationId(5000)).isNull.shouldBeTrue;

    testAnyOrder!SubStr(["error"]).shouldBeIn(r.output);
    testAnyOrder!SubStr([format!"Mutant with ID %s do not exist"(5000)]).shouldBeIn(r.output);
}

@(testId ~ "shall mark same mutant twice")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    // act
    // dfmt off
    auto firstRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        "3"])
        .addArg(["--to-status", to!string(Status.killedByCompiler)])
        .addArg(["--rationale", `"Backend claims mutant should not compile on target cpu"`])
        .run;
    auto secondRes = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        "3"])
        .addArg(["--to-status", to!string(Status.unknown)])
        .addArg(["--rationale", `"Backend was wrong, mutant is legit..."`])
        .run;

    // assert
    testAnyOrder!SubStr(["error"]).shouldNotBeIn(secondRes.output);
    testAnyOrder!SubStr([
        "3",
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
    auto db = createDatabase(testEnv);

    // act
    // dfmt off
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        "10"])
        .addArg(["--to-status", to!string(Status.killed)])
        .addArg(["--rationale", `"This marking should not exist"`])
        .run;
    db.isMarked(MutationId(10)).shouldBeTrue;
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        "10"])
        .run;
    // dfmt on

    // assert
    testAnyOrder!SubStr(["error"]).shouldNotBeIn(r.output);
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
    makeDextoolAnalyze(testEnv).addInputArg(dst).run;
    auto db = createDatabase(testEnv);

    // act
    // dfmt off
    auto r = makeDextoolAdmin(testEnv)
        .addArg(["--operation", "removeMarkedMutant"])
        .addArg(["--id",        "20"])
        .run;
    // dfmt on

    // assert
    db.isMarked(MutationId(20)).shouldBeFalse;

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

    // act
    // dfmt off
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        3.to!string])
        .addArg(["--to-status", to!string(Status.killedByCompiler)])
        .addArg(["--rationale", `"Lost"`])
        .run;

    auto r = makeDextoolAnalyze(testEnv).addInputArg(testData ~ "abs.cpp")
        .addArg("--force-save").run;

    // assert
    testAnyOrder!SubStr([ // only check filename, not absolutepath (order is assumed in stdout)
        "| ID |", " File ", "    | Line | Column | Status           | Rationale |",
        "|----|", "--------------|------|--------|------------------|-----------|",
        "| 3  |", `fibonacci.cpp | 8    | 8      | killedByCompiler | "Lost"    |`,
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
