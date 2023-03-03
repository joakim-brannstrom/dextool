/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-report_for_human

TODO the full test specification is not implemented.
*/
module dextool_test.test_report;

import core.time : dur, Duration;
import std.algorithm : map;
import std.array : array;
import std.conv : to;
import std.file : copy, exists, readText;
import std.path : buildPath, buildNormalizedPath, absolutePath, relativePath, setExtension;
import std.stdio : File;
import std.traits : EnumMembers;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;
static import dextool.type;

import dextool_test.fixtures;
import dextool_test.utility;

// dfmt off

@(testId ~ "shall report a summary of the untested mutants as human readable to stdout")
unittest {
    mixin(EnvSetup(globalTestdir));
    // Arrange
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;
    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName).run;

    testConsecutiveSparseOrder!SubStr([
        "Time spent:",
        "Score:",
        "Total:",
        "Untested:",
        "Alive:",
        "Killed:",
        "Timeout:",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall report the alive in the database as human readable to stdout")
unittest {
    mixin(EnvSetup(globalTestdir));
    // Arrange
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;
    auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
    auto ids = db.mutantApi.getAllMutationStatus;
    db.mutantApi.update(ids[0], Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "alive"])
        .addArg(["--section", "mut_stat"])
        .addArg(["--section", "summary"])
        .run;

    // TODO: there is a bug in the report because it do not deduplicate
    // similare mutants that occur on the same mutation point.
    testConsecutiveSparseOrder!Re([
        "alive from",
        `|\s*100\s*|\s*2\s*|\s*'>'\s*|\s*'!='\s*|`,
        "Summary",
        "Time spent:",
        "Score:",
        "Total:",
        "Untested:",
        "Alive:",
        "Killed:",
        "Timeout:",
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall report mutants in the database as gcc compiler warnings/notes with fixits to stderr")
unittest {
    mixin(EnvSetup(globalTestdir));

    auto src = AbsolutePath(testData ~ "report_one_ror_mutation_point.cpp");
    makeDextoolAnalyze(testEnv)
        .addInputArg(src)
        .addArg(["--mutant", "all"])
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "compiler"])
        .addArg(["--section", "all_mut"])
        .run;

    foreach (a;[
        [":6:9: warning: rorp: replace 'x > 3' with 'false'",
        ":6:9: note: status:unknown id:",
        `fix-it:"` ~ src.toString ~ `":{6:9-6:14}:"false"`],
        [":6:11: warning: ror: replace '>' with '!='",
        ":6:11: note: status:unknown id:",
        `fix-it:"` ~ src.toString ~ `":{6:11-6:12}:"!="`],
        [":6:11: warning: ror: replace '>' with '>='",
        ":6:11: note: status:unknown id:",
        `fix-it:"` ~ src.toString ~ `":{6:11-6:12}:">="`]]) {
        testConsecutiveSparseOrder!SubStr(a[]).shouldBeIn(r.output);
    }
}

@(testId ~ "shall report mutants as a json")
unittest {
    import std.json;

    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_tool_integration.cpp")
        .addArg(["--mutant", "dcr"])
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "json"])
        .addArg(["--section", "all_mut"])
        .addArg(["--section", "summary"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString))["stat"];
    j["alive"].integer.shouldEqual(0);
    j["alive_nomut"].integer.shouldEqual(0);
    j["killed"].integer.shouldEqual(0);
    j["killed_by_compiler"].integer.shouldEqual(0);
    j["killed_by_compiler_time_s"].integer.shouldEqual(0);
    try {
        // <2.079.0 compilers report this as an integer
        j["nomut_score"].floating.shouldEqual(0);
        j["score"].floating.shouldEqual(0);
    } catch(Exception e) {
    }
    j["predicted_done"].str; // lazy for now and just checking it is a string
    j["timeout"].integer.shouldEqual(0);
    j["total"].integer.shouldEqual(0);
    j["total_compile_time_s"].integer.shouldEqual(0);
    j["total_test_time_s"].integer.shouldEqual(0);
    j["untested"].integer.shouldBeGreaterThan(1);
}

@(testId ~ "shall report the mutation score history")
unittest {
    import std.json;

    mixin(EnvSetup(globalTestdir));

    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;

    makeDextool(testEnv).addArg(["test"]).addArg(["--mutant", "lcr"]).run;
    makeDextool(testEnv).addArg(["test"]).addArg(["--mutant", "lcr"]).run;
    makeDextool(testEnv).addArg(["test"]).addArg(["--mutant", "lcr"]).run;

    auto plain = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "plain"])
        .addArg(["--section", "trend"])
        .run;

    makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "json"])
        .addArg(["--section", "trend"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "html"])
        .addArg(["--section", "trend"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    testConsecutiveSparseOrder!Re([
        `| *Date *| *Score *|`,
        "|-*|",
        `|.*| *1 *|`
    ]).shouldBeIn(plain.output);

    auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString));
    try {
        // <2.079.0 compilers report this as an integer
        j["trend"]["score_history"][0]["score"].floating.shouldEqual(0);
    } catch(Exception e) {
    }
}

@(testId ~ "shall report test cases that kill the same mutants (overlap)")
unittest {
    // regression that the count of mutations are the total are correct (killed+timeout+alive)
    import dextool.plugin.mutate.backend.type : TestCase;

    mixin(EnvSetup(globalTestdir));
    // Arrange
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;
    auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

    const mutants = db.mutantApi.getAllMutationStatus;
    mutants.length.shouldBeGreaterThan(4);

    db.testCaseApi.setDetectedTestCases([TestCase("tc_4")]);

    db.mutantApi.update(mutants[0], Mutation.Status.killed,
            ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc1"), TestCase("tc2")]);
    db.mutantApi.update(mutants[0], Mutation.Status.killed,
            ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc1"), TestCase("tc2"), TestCase("tc_3")]);

    // make tc_3 unique
    db.mutantApi.update(mutants[2], Mutation.Status.killed,
            ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc_3")]);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "tc_full_overlap"])
        .addArg(["--style", "plain"])
        .run;

    makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "tc_full_overlap"])
        .addArg(["--style", "html"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    testConsecutiveSparseOrder!Re([
        "2/4 = 0.5 test cases",
        "| TestCase.*",
        "| tc_1.*",
        "| tc_2.*",
    ]).shouldBeIn(r.output);
}

class ShallReportTopTestCaseStats : ReportTestCaseStats {
    override void test() {
        import std.json;
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        auto db = precondition(testEnv);

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_stat"])
            .addArg(["--style", "plain"])
            .run;

         makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_stat"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

         makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_stat"])
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

         testConsecutiveSparseOrder!SubStr([
            "| Percentage | Count | TestCase |",
            "|------------|-------|----------|",
            "| 2     | tc_2     |",
            "| 1     | tc_3     |",
            "| 1     | tc_1     |",
         ]).shouldBeIn(r.output);

        testConsecutiveSparseOrder!SubStr([
            "Test Cases",
            `Normal 3`,
            `Normal`,
            "tc_1", "1",
            "tc_2", "2",
            "tc_3", "1"
        ]).shouldBeIn(File((testEnv.outdir ~ "html/index.html").toString).byLineCopy.array);

        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString));
        j["test_case_stat"]["tc_1"]["killed"].integer.shouldEqual(1);
        j["test_case_stat"]["tc_2"]["killed"].integer.shouldEqual(2);
        j["test_case_stat"]["tc_3"]["killed"].integer.shouldEqual(1);
    }
}

class ShallReportBottomTestCaseStats : ReportTestCaseStats {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_stat"])
            .addArg(["--style", "plain"])
            .addArg(["--section-tc_stat-num", "2"])
            .addArg(["--section-tc_stat-sort", "bottom"])
            .run;

        testConsecutiveSparseOrder!SubStr([
            "| Percentage | Count | TestCase |",
            "|------------|-------|----------|",
            "| 1     | tc_1     |",
            "| 1     | tc_3     |",
        ]).shouldBeIn(r.output);
    }
}

class ReportTestCaseStats : unit_threaded.TestCase {
    auto precondition(ref TestEnv testEnv) {
        import dextool.plugin.mutate.backend.type : TestCase;

        makeDextoolAnalyze(testEnv)
            .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
            .run;
        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        auto ids = db.mutantApi.getAllMutationStatus;
        assert(ids.length >= 4);

        // Updating this test case requires manually inspecting the database.
        //
        // By setting mutant 4 to killed it automatically propagate to mutant 5
        // because they are the same source code change.
        db.mutantApi.update(ids[0], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc_1"), TestCase("tc_2")]);
        db.mutantApi.update(ids[1], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"), [TestCase("tc_2"), TestCase("tc_3")]);
        db.mutantApi.update(ids[3], Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"));
        return db;
    }
}

@(testId ~ "shall report one marked mutant (plain)")
unittest {
    // arrange
    mixin(EnvSetup(globalTestdir));
    immutable dst = testEnv.outdir ~ "fibonacci.cpp";
    copy((testData ~ "fibonacci.cpp").toString, dst.toString);

    makeDextoolAnalyze(testEnv).addInputArg(dst).run;

    auto db = openDatabase(testEnv);
    const id = db.mutantApi.getAllMutationStatus[0].to!string;

    // act
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        id])
        .addArg(["--to-status", to!string(Mutation.Status.killedByCompiler)])
        .addArg(["--rationale", `"Marked mutant to be reported"`])
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section",   "marked_mutants"])
        .addArg(["--style",     "plain"])
        .run;

    // assert
    testAnyOrder!Re([ // only check filename, not absolutepath (order is assumed in stdout)
        "| File ", "        | Line | Column | Mutation.*| Status.*| Rationale                      |",
        "|", `fibonacci.cpp |.*|.*| '.*'->'.*' |.*| "Marked mutant to be reported" |`,
    ]).shouldBeIn(r.output);
}

class ShallReportTestCasesThatHasKilledZeroMutants : SimpleAnalyzeFixture {
    override void test() {
        // regression: the sum of all mutants shall be killed+timeout+alive
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        const mutants = db.mutantApi.getAllMutationStatus;
        mutants.length.shouldBeGreaterThan(4);

        db.testCaseApi.setDetectedTestCases([TestCase("tc_1"), TestCase("tc_2"), TestCase("tc_3"), TestCase("tc_4")]);
        db.mutantApi.update(mutants[0], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc_1"), TestCase("tc_2")]);
        db.mutantApi.update(mutants[1], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"), [TestCase("tc_2"), TestCase("tc_3")]);

        // Act
        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_killed_no_mutants"])
            .addArg(["--style", "plain"])
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_killed_no_mutants"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        testConsecutiveSparseOrder!SubStr([
            "| TestCase |",
            "|----------|",
            "| tc_4     |",
        ]).shouldBeIn(r.output);
    }
}

class ShallProduceHtmlReport : SimpleAnalyzeFixture {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        exists(buildPath(testEnv.outdir.toString, "html", "files", "plugin_testdata__report_one_ror_mutation_point.cpp.html")).shouldBeTrue;
        exists(buildPath(testEnv.outdir.toString, "html", "index.html")).shouldBeTrue;
    }
}

class ShallProduceHtmlReportWithWorklist : SimpleAnalyzeFixture {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextool(testEnv)
            .addArg(["test"])
            .addPostArg(["--max-runtime", "0 seconds"])
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        exists(buildPath(testEnv.outdir.toString, "html", "worklist.html")).shouldBeTrue;
    }
}

class ShallProduceHtmlReportOfMultiLineComment : SimpleAnalyzeFixture {
    override string programFile() {
        return (testData ~ "report_multi_line_comment.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        testConsecutiveSparseOrder!SubStr([
            `"loc-7"`,
            `"loc-8"`,
            `"loc-9"`,
            `"loc-10"`,
            `"loc-11"`,
            `"loc-12"`,
            `"loc-13"`,
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "files", "plugin_testdata__report_multi_line_comment.cpp.html")).byLineCopy.array);
    }
}

class ShallReportAliveMutantsOnChangedLine : SimpleAnalyzeFixture {
    override void test() {
        import std.json;
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        const file1 = dextool.type.Path(relativePath(programFile, workDir.toString));
        const fid = db.getFileId(file1);
        fid.isNull.shouldBeFalse;
        auto mutants = db.mutantApi.getMutationsOnLine(fid.get, SourceLoc(6,0));
        foreach (id; mutants[0 .. $/3]) {
            db.mutantApi.update(id, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        }
        foreach (id; mutants[$/3 .. $]) {
            db.mutantApi.update(id, Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        }

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .addArg("--diff-from-stdin")
            .addArg(["--section", "diff"])
            .setStdin(readText(programFile ~ ".diff"))
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .addArg("--diff-from-stdin")
            .addArg(["--section", "diff"])
            .setStdin(readText(programFile ~ ".diff"))
            .run;

        // Assert
        testConsecutiveSparseOrder!SubStr(["warning:"]).shouldNotBeIn(r.output);

        testConsecutiveSparseOrder!SubStr([
            "Diff View",
            "Mutation Score <b>0.8",
            "Analyzed Diff",
            "plugin_testdata/report_one_ror_mutation_point.cpp",
        ]).shouldBeIn(File((testEnv.outdir ~ "html/diff_view.html").toString).byLineCopy.array);

        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString))["diff"];
        (cast(int) (10 * j["score"].floating)).shouldEqual(8);
    }
}

class LinesWithNoMut : SimpleAnalyzeFixture {
    override string programFile() {
        return (testData ~ "report_nomut1.cpp").toString;
    }
}

class ShallReportMutationScoreAdjustedByNoMut : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        auto ids = db.mutantApi.getAllMutationStatus;

        foreach (id; ids)
            db.mutantApi.update(id, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));

        auto plain = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "summary"])
            .addArg(["--style", "plain"])
            .run;

        // TODO how to verify this? arsd.dom?
        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!Re([
            "Score:.*0",
            "Total:.*8",
            "Alive:.*8",
            "Killed:.*0",
            "Timeout:.*0",
            "Killed by compiler:.*0",
            "Suppressed .nomut.:.*3 .0.375",
        ]).shouldBeIn(plain.output);
    }
}

class ShallReportHtmlMutationScoreAdjustedByNoMut : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (id; db.mutantApi.getAllMutationStatus)
            db.mutantApi.update(id, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        testConsecutiveSparseOrder!SubStr([
            "Mutation Score <b>0</b>",
            "Total",
            "8",
            "Killed by compiler",
            "0",
            "NoMut",
            "3",
            "NoMut/total",
            "0.3",
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "index.html")).byLineCopy.array);
    }
}

class ShallReportHtmlNoMutForMutantsInFileView : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        const mutants = db.mutantApi.getAllMutationStatus;
        mutants.length.shouldBeGreaterThan(7);

        foreach (id; mutants[0..4])
            db.mutantApi.update(id, Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        foreach (id; mutants[4..8])
            db.mutantApi.update(id, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // this is a bit inprecies but there should be a couple, unknown the
        // number, of mutants without any metadata. Then there should be some
        // with nomut.
        testConsecutiveSparseOrder!SubStr([
            "'meta' : ''",
            "'meta' : ''",
            "'meta' : ''",
            "'meta' : 'nomut'",
            "'meta' : 'nomut'",
            ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "files", "plugin_testdata__report_nomut1.cpp.html")).byLineCopy.array);
    }
}

class ShallReportHtmlNoMutSummary : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (id; db.mutantApi.getAllMutationStatus)
            db.mutantApi.update(id, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
                `<h2>group1</h2>`,
                `<a href="files/plugin_testdata__report_nomut1.cpp.html`,
                `<br`, `with comment`
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "nomut.html")).byLineCopy.array);
    }
}

class ShallReportHtmlTestCaseSimilarity : LinesWithNoMut {
    import dextool.plugin.mutate.backend.type : TestCase;

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        auto ids = db.mutantApi.getAllMutationStatus;

        const tc1 = TestCase("tc_1");
        const tc2 = TestCase("tc_2");
        const tc3 = TestCase("tc_3");
        // tc1: [0,1,2,3,4]
        // tc2: [0,2,3,4]
        // tc3: [0,3]
        db.mutantApi.update(ids[0], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.mutantApi.update(ids[1], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
        db.mutantApi.update(ids[2], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.mutantApi.update(ids[3], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.mutantApi.update(ids[4], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--section", "tc_similarity"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        testConsecutiveSparseOrder!SubStr([
                                          `Similarity`,
                `tc_2`, `<td>0.8`, `tc_3`, `<td>0.4`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_cases", "tc_1.html")).byLineCopy.array);
        testConsecutiveSparseOrder!SubStr([
                                          `Similarity`,
                `tc_1`, `<td>1.0`, `tc_3`, `<td>0.5`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_cases", "tc_2.html")).byLineCopy.array);
        testConsecutiveSparseOrder!SubStr([
                                          `Similarity`,
                `tc_1`, `<td>1.0`, `tc_2`, `<td>1.0`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_cases", "tc_3.html")).byLineCopy.array);
    }
}

class ShallReportTestCaseUniqueness : LinesWithNoMut {
    override void test() {
        import std.json;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        auto ids = db.mutantApi.getAllMutationStatus;

        import dextool.plugin.mutate.backend.type : TestCase;

        // Arrange
        const tc1 = TestCase("tc_1");
        const tc2 = TestCase("tc_2");
        const tc3 = TestCase("tc_3");
        // tc1: [0,1,2,3,4]
        // tc2: [0,2,3,4]
        // tc3: [0,3]
        db.mutantApi.update(ids[0], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.mutantApi.update(ids[1], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
        db.mutantApi.update(ids[2], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.mutantApi.update(ids[3], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.mutantApi.update(ids[4], Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);

        // Act
        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_unique"])
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // Assert
        testConsecutiveSparseOrder!SubStr([
                `Test Cases</h2>`, `Unique 1`, `Unique`, `tc_1`, `Redundant`
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "index.html")).byLineCopy.array);

        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString));
        j["test_case_no_unique"].array.length.shouldEqual(2);
    }
}

class ShallExcludeNewTcFromBuggy : LinesWithNoMut {
    override void test() {
        import std.json;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        import dextool.plugin.mutate.backend.type : TestCase;

        // Arrange
        const tc1 = TestCase("tc_1");
        db.testCaseApi.setDetectedTestCases([tc1]);

        // Act
        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", (testEnv.outdir ~ "excluded").toString])
            .run;

        db.testCaseApi.removeNewTestCaseTag;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        testConsecutiveSparseOrder!SubStr([
                `Test Cases</h2>`, `>Unique<`, `>Redundant<`, `>Buggy 1<`
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "index.html")).byLineCopy.array);

        testConsecutiveSparseOrder!SubStr([
                `Test Cases</h2>`, `>Unique<`, `>Redundant<`, `>Buggy<`
                ]).shouldBeIn(File(buildPath((testEnv.outdir ~ "excluded").toString, "html",
                "index.html")).byLineCopy.array);
    }
}

class ShallReportMutationScoreTrend : SimpleAnalyzeFixture {
    override void test() {
        import std.json;
        import std.datetime : Clock;
        import std.range : enumerate;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        auto ts = Clock.currTime - 2.dur!"weeks";
        foreach (d; 0 .. 50) {
                db.fileApi.put(FileScore(ts + d.dur!"days", typeof(FileScore.score)(0.2 + 0.05*d), Path("foo.d")));
                db.putMutationScore(MutationScore(ts + d.dur!"days", typeof(MutationScore.score)(0.2 + 0.05*d)));
        }
        foreach (d; 5 .. 50) {
                db.fileApi.put(FileScore(ts + d.dur!"days", typeof(FileScore.score)(0.2 + 0.05*5 - 0.01*d), Path("foo.d")));
                db.putMutationScore(MutationScore(ts + d.dur!"days", typeof(MutationScore.score)(0.2 + 0.05*d - 0.01*d)));
        }

        foreach (id; db.mutantApi.getAllMutationStatus.enumerate)
            db.mutantApi.update(id.value, id.index % 3 == 0 ? Mutation.Status.alive : Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "trend"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "trend"])
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;
    }
}

class ShallChangeNrOfHighInterestMutantsShown : SimpleAnalyzeFixture {
    import dextool.plugin.mutate.backend.type : TestCase;

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        foreach (id; db.mutantApi.getAllMutationStatus)
            db.mutantApi.update(id, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), []);

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .addArg(["--high-interest-mutants-nr", "10"])
            .run;

        testConsecutiveSparseOrder!SubStr([
            "High Interest Mutants",
            "report_one_ror_mutation_point",
            "report_one_ror_mutation_point",
            "report_one_ror_mutation_point",
            "report_one_ror_mutation_point",
            "report_one_ror_mutation_point",
            "report_one_ror_mutation_point",
            "report_one_ror_mutation_point",
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "index.html")).byLineCopy.array);
    }
}

// this test only see that the database queries work
class ShallReportHtmlMutantSuggestion : SimpleAnalyzeFixture {
    import dextool.plugin.mutate.backend.type : TestCase;

    override void test() {
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        auto ids = db.mutantApi.getAllMutationStatus;

        foreach (i; ids[0 .. $/2])
            db.mutantApi.update(i, Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc_1")]);
        foreach (i; ids[$/2 .. $])
            db.mutantApi.update(i, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--section", "tc_suggestion"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // only check that the column exists, not the content. checking the
        // content becomes so specific which may lead to a brittle test
        testConsecutiveSparseOrder!SubStr([`Suggestion`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_cases", "tc_1.html")).byLineCopy.array);
    }
}

class ShallReportHtmlForTestCaseUsingTestMetadata : SimpleAnalyzeFixture {
    import std.range : enumerate;
    import dextool.plugin.mutate.backend.type : TestCase;

    override string programFile() {
        return (testData ~ "complex_example.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        immutable dst = testEnv.outdir ~ "metadata.json";
        copy((testData ~ "testcase_metadata.json").toString, dst.toString);
        File((testEnv.outdir ~ "tc_1.cpp").toString, "w").writeln("int main() {}");

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        auto ids = db.mutantApi.getAllMutationStatus;

        const tc1 = TestCase("tc_1");
        const tc2 = TestCase("tc_2");
        const tc3 = TestCase("tc_3");

        {
            auto t = db.transaction;
            foreach (id; ids.enumerate) {
                if (id.index % 2 == 0)
                    db.mutantApi.update(id.value, Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
                else if (id.index % 3 == 0)
                    db.mutantApi.update(id.value, Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
                else
                    db.mutantApi.update(id.value, Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
            }
            t.commit;
        }

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--test-metadata", dst])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        testConsecutiveSparseOrder!Re([`tc_1.cpp.*at line.*42.*a text with.*links`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_cases", "tc_1.html")).byLineCopy.array);
    }
}
