/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-report_for_human

TODO the full test specification is not implemented.
*/
module dextool_test.test_report;

import core.time : dur, Duration;
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
        "Mutation operators: lcr, lcrb, sdl, uoi, dcr",
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
    db.updateMutation(MutationId(1), Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addPostArg(["--mutant", "all"])
        .addArg(["--section", "alive"])
        .addArg(["--section", "mut_stat"])
        .addArg(["--section", "summary"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "Mutation operators: all",
        "alive from",
        "| Percentage | Count | From | To         |",
        "|------------|-------|------|------------|",
        "| 100        | 1     | `x`  | `fail_...` |",
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
    auto input_src = testData ~ "report_one_ror_mutation_point.cpp";
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(input_src)
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "ror"])
        .addArg(["--style", "compiler"])
        .addArg(["--section", "all_mut"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        ":6:9: warning: rorp: replace 'x > 3' with 'false'",
        ":6:9: note: status:unknown id:",
        `fix-it:"` ~ input_src.toString ~ `":{6:9-6:14}:"false"`,
        ":6:11: warning: ror: replace '>' with '!='",
        ":6:11: note: status:unknown id:",
        `fix-it:"` ~ input_src.toString ~ `":{6:11-6:12}:"!="`,
        ":6:11: warning: ror: replace '>' with '>='",
        ":6:11: note: status:unknown id:",
        `fix-it:"` ~ input_src.toString ~ `":{6:11-6:12}:">="`,
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall report mutants as a json")
unittest {
    import std.json;

    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_tool_integration.cpp")
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "dcr"])
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
    j["nomut_score"].integer.shouldEqual(0);
    j["predicted_done"].str; // lazy for now and just checking it is a string
    j["score"].integer.shouldEqual(0);
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
        .addArg(["--section", "score_history"])
        .run;

    makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "json"])
        .addArg(["--section", "score_history"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "html"])
        .addArg(["--section", "score_history"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    testConsecutiveSparseOrder!Re([
        `| *Date *| *Score *|`,
        "|-*|",
        `|.*| *1 *|`
    ]).shouldBeIn(plain.output);

    auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString));
    j["score_history"][0]["score"].integer.shouldEqual(0);
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

    db.setDetectedTestCases([TestCase("tc_4")]);
    db.updateMutation(MutationId(1), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc_1"), TestCase("tc_2")]);
    db.updateMutation(MutationId(2), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"), [TestCase("tc_1"), TestCase("tc_2"), TestCase("tc_3")]);
    // make tc_3 unique
    db.updateMutation(MutationId(4), Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"), [TestCase("tc_3")]);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addPostArg(["--mutant", "all"])
        .addArg(["--section", "tc_full_overlap"])
        .addArg(["--style", "plain"])
        .run;

    makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "tc_full_overlap"])
        .addArg(["--style", "html"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "2/4 = 0.5 test cases",
        "| TestCase |",
        "|----------|",
        "| tc_1     |",
        "| tc_2     |",
    ]).shouldBeIn(r.output);
}

class ShallReportTopTestCaseStats : ReportTestCaseStats {
    override void test() {
        import std.json;
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        auto db = precondition(testEnv);

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "tc_stat"])
            .addArg(["--style", "plain"])
            .run;

         makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "tc_stat"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

         makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "tc_stat"])
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

         testConsecutiveSparseOrder!SubStr([
            "| Percentage | Count | TestCase |",
            "|------------|-------|----------|",
            "| 66.6667    | 2     | tc_2     |",
            "| 33.3333    | 1     | tc_3     |",
            "| 33.3333    | 1     | tc_1     |",
         ]).shouldBeIn(r.output);

        testConsecutiveSparseOrder!SubStr([
            "Test Case Statistics",
            "0.67", "2", "tc_2",
            "0.33", "1", "tc_3",
            "0.33", "1", "tc_1",
        ]).shouldBeIn(File((testEnv.outdir ~ "html/test_case_stat.html").toString).byLineCopy.array);

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
            .addPostArg(["--mutant", "all"])
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

        // Updating this test case requires manually inspecting the database.
        //
        // By setting mutant 4 to killed it automatically propagate to mutant 5
        // because they are the same source code change.
        db.updateMutation(MutationId(1), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc_1"), TestCase("tc_2")]);
        db.updateMutation(MutationId(4), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"), [TestCase("tc_2"), TestCase("tc_3")]);
        db.updateMutation(MutationId(7), Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"), null);
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

    // act
    makeDextoolAdmin(testEnv)
        .addArg(["--operation", "markMutant"])
        .addArg(["--id",        to!string(3)])
        .addArg(["--to-status", to!string(Mutation.Status.killedByCompiler)])
        .addArg(["--rationale", `"Marked mutant to be reported"`])
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section",   "marked_mutants"])
        .addArg(["--style",     "plain"])
        .run;

    // assert
    testAnyOrder!SubStr([ // only check filename, not absolutepath (order is assumed in stdout)
        "| File ", "        | Line | Column | Mutation               | Status           | Rationale                      |",
        "|------", "--------|------|--------|------------------------|------------------|--------------------------------|",
        "|", `fibonacci.cpp | 8    | 8      | 'x'->'-abs_dextool(x)' | killedByCompiler | "Marked mutant to be reported" |`,
    ]).shouldBeIn(r.output);
}

class ShallReportTestCasesThatHasKilledZeroMutants : SimpleAnalyzeFixture {
    override void test() {
        // regression: the sum of all mutants shall be killed+timeout+alive
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        db.setDetectedTestCases([TestCase("tc_1"), TestCase("tc_2"), TestCase("tc_3"), TestCase("tc_4")]);
        db.updateMutation(MutationId(1), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [TestCase("tc_1"), TestCase("tc_2")]);
        db.updateMutation(MutationId(2), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 10.dur!"msecs"), [TestCase("tc_2"), TestCase("tc_3")]);

        // Act
        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "tc_killed_no_mutants"])
            .addArg(["--style", "plain"])
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
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

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert that the expected files have been generated
        exists(buildPath(testEnv.outdir.toString, "html", "files", "build_plugin_mutate_plugin_testdata_report_one_ror_mutation_point.cpp.html")).shouldBeTrue;
        exists(buildPath(testEnv.outdir.toString, "html", "stats.html")).shouldBeTrue;
        exists(buildPath(testEnv.outdir.toString, "html", "index.html")).shouldBeTrue;
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
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "files", "build_plugin_mutate_plugin_testdata_report_multi_line_comment.cpp.html")).byLineCopy.array);
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
        auto mutants = db.getMutationsOnLine([EnumMembers!(Mutation.Kind)], fid.get, SourceLoc(6,0));
        foreach (id; mutants[0 .. $/3]) {
            db.updateMutation(id, Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        }
        foreach (id; mutants[$/3 .. $]) {
            db.updateMutation(id, Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"));
        }

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .addArg("--diff-from-stdin")
            .addArg(["--section", "diff"])
            .setStdin(readText(programFile ~ ".diff"))
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
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
            "Mutation Score <b>0.6",
            "Analyzed Diff",
            "build/plugin/mutate/plugin_testdata/report_one_ror_mutation_point.cpp",
        ]).shouldBeIn(File((testEnv.outdir ~ "html/diff_view.html").toString).byLineCopy.array);

        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString))["diff"];
        (cast(int) (10 * j["score"].floating)).shouldEqual(6);
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

        foreach (i; 0 .. 15)
            db.updateMutation(MutationId(i), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);

        auto plain = makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "plain"])
            .run;

        // TODO how to verify this? arsd.dom?
        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!Re([
            "Score:.*0.64",
            "Total:.*25",
            "Untested:.*36",
            "Alive:.*14",
            "Killed:.*11",
            "Timeout:.*0",
            "Killed by compiler:.*0",
            "Suppressed .nomut.:.*8 .0.32",
        ]).shouldBeIn(plain.output);
    }
}

class ShallReportHtmlMutationScoreAdjustedByNoMut : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (i; 0 .. 15)
            db.updateMutation(MutationId(i), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);

        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
            "Mutation Score <b>",
            "Total",
            "25",
            "Untested",
            "36",
            "Alive",
            "14",
            "Killed",
            "11",
            "Timeout",
            "0",
            "Killed by compiler",
            "0",
            "NoMut",
            "8",
            "NoMut/total",
            "0.32",
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "stats.html")).byLineCopy.array);
    }
}

class ShallReportHtmlNoMutForMutantsInFileView : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (i; 0 .. 15)
            db.updateMutation(MutationId(i), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);

        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
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
            ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "files", "build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html")).byLineCopy.array);
}
}

class ShallReportHtmlNoMutSummary : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (i; 0 .. 15)
            db.updateMutation(MutationId(i), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), null);

        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
                `<h2>group1</h2>`,
                `<a href="files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html`,
                `<br`, `with comment`
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "nomut.html")).byLineCopy.array);
    }
}

class ShallReportHtmlTestCaseSimilarity : LinesWithNoMut {
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
        db.updateMutation(MutationId(1), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.updateMutation(MutationId(3), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
        db.updateMutation(MutationId(8), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.updateMutation(MutationId(12), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.updateMutation(MutationId(15), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);

        // Act
        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--style", "html"])
            .addArg(["--section", "tc_similarity"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // Assert
        testConsecutiveSparseOrder!SubStr([
                `<h2 class="tbl_header"><i class="right"></i> tc_1</h2>`,
                `<td>tc_2`, `<td>0.8`, `<td>tc_3`, `<td>0.4`,
                `<h2 class="tbl_header"><i class="right"></i> tc_2</h2>`,
                `<td>tc_1`, `<td>1.00`, `<td>tc_3`, `<td>0.5`,
                `<h2 class="tbl_header"><i class="right"></i> tc_3</h2>`,
                `<td>tc_1`, `<td>1.00`, `<td>tc_2`, `<td>1.00`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_case_similarity.html")).byLineCopy.array);
    }
}

class ShallReportTestCaseUniqueness : LinesWithNoMut {
    override void test() {
        import std.json;

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
        db.updateMutation(MutationId(1), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.updateMutation(MutationId(3), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1]);
        db.updateMutation(MutationId(8), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);
        db.updateMutation(MutationId(12), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2, tc3]);
        db.updateMutation(MutationId(15), Mutation.Status.killed, ExitStatus(0), MutantTimeProfile(Duration.zero, 5.dur!"msecs"), [tc1, tc2]);

        // Act
        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--style", "html"])
            .addArg(["--section", "tc_unique"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "tc_unique"])
            .addArg(["--style", "json"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // Assert
        testConsecutiveSparseOrder!SubStr([
                `<h2 class="tbl_header"><i class="right"></i> tc_1</h2>`,
                `<table class="overlap_tbl">`, `<td>tc_2</td>`, `<td>tc_3</td>`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_case_unique.html")).byLineCopy.array);

        auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString));
        j["test_case_no_unique"].array.length.shouldEqual(3);
    }
}
