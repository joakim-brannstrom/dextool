/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-report_for_human

TODO the full test specification is not implemented.
*/
module dextool_test.test_report;

import core.time : dur;
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
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "markdown"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "# Mutation Type",
        "## Summary",
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
    db.updateMutation(MutationId(1), Mutation.Status.alive, 5.dur!"msecs", null);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addPostArg(["--mutant", "all"])
        .addArg(["--level", "alive"])
        .addArg(["--style", "markdown"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "# Mutation Type",
        "## Mutants",
        "| From | To         | File Line:Column                                                          | ID | Status |",
        "|------|------------|---------------------------------------------------------------------------|----|--------|",
        "| `x`  | `fail_...` | build/plugin/mutate/plugin_testdata/report_one_ror_mutation_point.cpp 6:9 | 1  | alive  |",
        "## Alive Mutation Statistics",
        "| Percentage | Count | From | To         |",
        "|------------|-------|------|------------|",
        "| 100        | 1     | `x`  | `fail_...` |",
        "## Summary",
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
        .addArg(["--level", "all"])
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

    auto input_src = testData ~ "report_tool_integration.cpp";
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(input_src)
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "dcc"])
        .addArg(["--style", "json"])
        .addArg(["--section", "all_mut"])
        .addArg(["--section", "summary"])
        .addArg(["--logdir", testEnv.outdir.toString])
        .run;

    auto j = parseJSON(readText((testEnv.outdir ~ "report.json").toString))["stat"];
    j["alive"].integer.shouldEqual(0);
    j["aliveNoMut"].integer.shouldEqual(0);
    j["killed"].integer.shouldEqual(0);
    j["killedByCompiler"].integer.shouldEqual(0);
    j["killedByCompilerTime"].integer.shouldEqual(0);
    j["nomutScore"].integer.shouldEqual(0);
    j["predictedDone"].str; // lazy for now and just checking it is a string
    j["score"].integer.shouldEqual(0);
    j["timeout"].integer.shouldEqual(0);
    j["total"].integer.shouldEqual(0);
    j["totalTime"].integer.shouldEqual(0);
    j["untested"].integer.shouldEqual(7);
}

@(testId ~ "shall report mutants in csv format")
unittest {
    //#TST-report_as_csv

    auto input_src = testData ~ "report_as_csv.cpp";
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(input_src)
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--style", "csv"])
        .addArg(["--level", "all"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        `"ID","Kind","Description","Location","Comment"`,
        `"dcr","'var1_long_text >5' to 'true'","build/plugin/mutate/plugin_testdata/report_as_csv.cpp:7:9",""`,
        `"dcr","'var1_long_text >5' to 'false'","build/plugin/mutate/plugin_testdata/report_as_csv.cpp:7:9",""`,
        `"dcr","'case 2:`,
        `        return true;' to ''","build/plugin/mutate/plugin_testdata/report_as_csv.cpp:11:5",""`,
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall report test cases with how many mutants killed correctly counting the sum of mutants as two")
unittest {
    // regression that the count of mutations are the total are correct (killed+timeout+alive)
    import dextool.plugin.mutate.backend.type : TestCase;

    mixin(EnvSetup(globalTestdir));
    // Arrange
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;
    auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
    // Updating this test case requires manually inspecting the database.
    //
    // The mutation ID's are chosen in such a way that 1 and 2 is the same.
    // This mean that the second updateMutation will overwrite whatever 1 was
    // set to.
    //
    // By setting mutant 4 to killed it automatically propagate to mutant 5
    // because they are the same source code change.
    //
    // Then tc_1 is added to mutant 4 because it makes the score of the test
    // suite sto be different when it is based on the distinct mutants killed.
    db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [TestCase("tc_1"), TestCase("tc_2")]);
    db.updateMutation(MutationId(2), Mutation.Status.killed, 10.dur!"msecs", [TestCase("tc_2"), TestCase("tc_3")]);
    db.updateMutation(MutationId(4), Mutation.Status.killed, 5.dur!"msecs", [TestCase("tc_1"), TestCase("tc_2")]);
    db.updateMutation(MutationId(7), Mutation.Status.alive, 10.dur!"msecs", null);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addPostArg(["--mutant", "all"])
        .addArg(["--section", "tc_stat"])
        .addArg(["--style", "plain"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "| Percentage | Count | TestCase |",
        "|------------|-------|----------|",
        "| 60         | 3     | tc_2     |",
        "| 40         | 2     | tc_1     |",
        "| 20         | 1     | tc_3     |",
    ]).shouldBeIn(r.output);
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
    db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [TestCase("tc_1"), TestCase("tc_2")]);
    db.updateMutation(MutationId(2), Mutation.Status.killed, 10.dur!"msecs", [TestCase("tc_1"), TestCase("tc_2"), TestCase("tc_3")]);
    // make tc_3 unique
    db.updateMutation(MutationId(4), Mutation.Status.alive, 10.dur!"msecs", [TestCase("tc_3")]);

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

@(testId ~ "shall report the bottom (least killed) test cases stat of how many mutants they killed")
unittest {
    // regression that the count of mutations are the total are correct (killed+timeout+alive)
    import dextool.plugin.mutate.backend.type : TestCase;

    mixin(EnvSetup(globalTestdir));
    // Arrange
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;
    auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
    db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [TestCase("tc_1"), TestCase("tc_2")]);
    db.updateMutation(MutationId(4), Mutation.Status.killed, 10.dur!"msecs", [TestCase("tc_2"), TestCase("tc_3")]);
    db.updateMutation(MutationId(7), Mutation.Status.alive, 10.dur!"msecs", null);

    // Act
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
        "| 0.333333   | 1     | tc_1     |",
        "| 0.333333   | 1     | tc_3     |",
    ]).shouldBeIn(r.output);
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
        "| File ", "        | Line | Column | Mutation        | Status           | Rationale                      |",
        "|------", "--------|------|--------|-----------------|------------------|--------------------------------|",
        "|", `fibonacci.cpp | 8    | 8      | -abs_dextool(x) | killedByCompiler | "Marked mutant to be reported" |`,
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
        db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [TestCase("tc_1"), TestCase("tc_2")]);
        db.updateMutation(MutationId(2), Mutation.Status.killed, 10.dur!"msecs", [TestCase("tc_2"), TestCase("tc_3")]);

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
            db.updateMutation(id, Mutation.Status.alive, 5.dur!"msecs");
        }
        foreach (id; mutants[$/3 .. $]) {
            db.updateMutation(id, Mutation.Status.killed, 5.dur!"msecs");
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

class ShallTagLinesWithNoMutAttr : LinesWithNoMut {
    override void test() {
        import sumtype;
        import dextool.plugin.mutate.backend.database.type;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        // assert
        const file1 = dextool.type.Path(relativePath(programFile, workDir.toString));
        const file2 = dextool.type.Path(relativePath(programFile.setExtension("hpp"), workDir.toString));
        auto fid = db.getFileId(file1);
        auto fid2 = db.getFileId(file2);
        fid.isNull.shouldBeFalse;
        fid2.isNull.shouldBeFalse;
        foreach (line; [11,12,14,24,32]) {
            auto m = db.getLineMetadata(fid.get, SourceLoc(line,0));
            m.attr.match!((NoMetadata a) {shouldBeFalse(true);},
                     (NoMut) {
                         m.id.shouldEqual(fid);
                         m.line.shouldEqual(line);
            });
        }
        foreach (line; [8,9])
            db.getLineMetadata(fid.get, SourceLoc(line,0)).isNoMut.shouldBeFalse;
    }
}

class ShallReportMutationScoreAdjustedByNoMut : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (i; 0 .. 15)
            db.updateMutation(MutationId(i), Mutation.Status.killed, 5.dur!"msecs", null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, 5.dur!"msecs", null);

        auto plain = makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "plain"])
            .run;

        auto markdown = makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "markdown"])
            .run;

        // TODO how to verify this? arsd.dom?
        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
            "Score:       0.5",
            "Total:       26",
            "Untested:    34",
            "Alive:       15",
            "Killed:      11",
            "Timeout:     0",
            "Killed by compiler: 0",
            "Suppressed (nomut): 4 (0.15",
        ]).shouldBeIn(plain.output);

        testConsecutiveSparseOrder!SubStr([
            "Score:       0.5",
            "Total:       26",
            "Untested:    34",
            "Alive:       15",
            "Killed:      11",
            "Timeout:     0",
            "Killed by compiler: 0",
            "Suppressed (nomut): 4 (0.15",
        ]).shouldBeIn(markdown.output);
    }
}

class ShallReportHtmlMutationScoreAdjustedByNoMut : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (i; 0 .. 15)
            db.updateMutation(MutationId(i), Mutation.Status.killed, 5.dur!"msecs", null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, 5.dur!"msecs", null);

        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
            "Mutation Score <b>0.5</b>",
            "Total",
            "26",
            "Untested",
            "34",
            "Alive",
            "15",
            "Killed",
            "11",
            "Timeout",
            "0",
            "Killed by compiler",
            "0",
            "NoMut",
            "4",
            "NoMut/total",
            "0.15",
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "stats.html")).byLineCopy.array);
    }
}

class ShallReportHtmlNoMutForMutantsInFileView : LinesWithNoMut {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

        foreach (i; 0 .. 15)
            db.updateMutation(MutationId(i), Mutation.Status.killed, 5.dur!"msecs", null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, 5.dur!"msecs", null);

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
            db.updateMutation(MutationId(i), Mutation.Status.killed, 5.dur!"msecs", null);
        foreach (i; 15 .. 30)
            db.updateMutation(MutationId(i), Mutation.Status.alive, 5.dur!"msecs", null);

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

        // mutants should only be reported one time.
        testConsecutiveSparseOrder!SubStr([
                `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#28`,
                `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#28`,
                `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#29`,
                `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#29`,
                ]).shouldNotBeIn(File(buildPath(testEnv.outdir.toString,
                "html", "nomut.html")).byLineCopy.array);
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
        db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2, tc3
                ]);
        db.updateMutation(MutationId(3), Mutation.Status.killed, 5.dur!"msecs", [
                tc1
                ]);
        db.updateMutation(MutationId(8), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2
                ]);
        db.updateMutation(MutationId(12), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2, tc3
                ]);
        db.updateMutation(MutationId(15), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2
                ]);

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
                `<td>tc_2`, `<td>0.8`, `<td>tc_3`, `<td>0.2`,
                `<h2 class="tbl_header"><i class="right"></i> tc_2</h2>`,
                `<td>tc_1`, `<td>1.00`, `<td>tc_3`, `<td>0.2`,
                `<h2 class="tbl_header"><i class="right"></i> tc_3</h2>`,
                `<td>tc_1`, `<td>1.00`, `<td>tc_2`, `<td>1.00`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_case_similarity.html")).byLineCopy.array);
    }
}

class ShallReportTestCaseUniqueness : LinesWithNoMut {
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
        db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2, tc3
                ]);
        db.updateMutation(MutationId(3), Mutation.Status.killed, 5.dur!"msecs", [
                tc1
                ]);
        db.updateMutation(MutationId(8), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2
                ]);
        db.updateMutation(MutationId(12), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2, tc3
                ]);
        db.updateMutation(MutationId(15), Mutation.Status.killed, 5.dur!"msecs", [
                tc1, tc2
                ]);

        // Act
        makeDextoolReport(testEnv, testData.dirName)
            .addPostArg(["--mutant", "all"])
            .addArg(["--style", "html"])
            .addArg(["--section", "tc_unique"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // Assert
        testConsecutiveSparseOrder!SubStr([
                `<h2 class="tbl_header"><i class="right"></i> tc_1</h2>`,
                `<table class="overlap_tbl">`, `<td>tc_2</td>`, `<td>tc_3</td>`,
                ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html",
                "test_case_unique.html")).byLineCopy.array);
    }
}
