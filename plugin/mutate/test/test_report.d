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
import std.file : exists, readText;
import std.path : buildPath, buildNormalizedPath, absolutePath, relativePath, setExtension;
import std.stdio : File;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;
static import dextool.type;

import dextool_test.utility;
import dextool_test.fixtures;

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
    ]).shouldBeIn(r.stdout);
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
        .addArg(["--level", "alive"])
        .addArg(["--style", "markdown"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "# Mutation Type",
        "## Mutants",
        "| From | To   | File Line:Column                                                           | ID | Status |",
        "|------|------|----------------------------------------------------------------------------|----|--------|",
        "| `>`  | `>=` | build/plugin/mutate/plugin_testdata/report_one_ror_mutation_point.cpp 6:11 | 1  | alive  |",
        "## Alive Mutation Statistics",
        "| Percentage | Count | From | To   |",
        "|------------|-------|------|------|",
        "| 100        | 2     | `>`  | `>=` |",
        "## Summary",
        "Time spent:",
        "Score:",
        "Total:",
        "Untested:",
        "Alive:",
        "Killed:",
        "Timeout:",
    ]).shouldBeIn(r.stdout);
}

@(testId ~ "shall report the ROR mutations in the database as gcc compiler warnings/notes with fixits to stderr")
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
                      ":6:11: warning: ror: replace '>' with '>='",
                      ":6:11: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{6:11-6:12}:">="`,
                      ":6:11: warning: ror: replace '>' with '!='",
                      ":6:11: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{6:11-6:12}:"!="`,
                      ":6:9: warning: rorp: replace 'x > 3' with 'false'",
                      ":6:9: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{6:9-6:14}:"false"`,
    ]).shouldBeIn(r.stderr);
}

@(testId ~ "shall report tool integration notes with the full text for dccTrue and dccBomb")
unittest {
    auto input_src = testData ~ "report_tool_integration.cpp";
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(input_src)
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "dcc"])
        .addArg(["--style", "compiler"])
        .addArg(["--level", "all"])
        .run;

    testConsecutiveSparseOrder!SubStr([
                      ":7:9: warning: dcr: replace 'var1_...' with 'true'",
                      ":7:9: note: status:unknown id:",
                      ":7:9: note: replace 'var1_long_text > 5'",
                      `fix-it:"` ~ input_src.toString ~ `":{7:9-7:27}:"true"`,
                      ":11:5: warning: dcc: replace 'retur...' with '*((ch...'",
                      ":11:5: note: status:unknown id:",
                      ":11:5: note: replace 'return true;'",
                      ":11:5: note: with '*((char*)0)='x';break;'",
                      `fix-it:"` ~ input_src.toString ~ `":{11:5-12:20}:"*((char*)0)='x';break;"`,
    ]).shouldBeIn(r.stderr);
}

@(testId ~ "shall report mutants as a json")
unittest {
    auto input_src = testData ~ "report_tool_integration.cpp";
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(input_src)
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "dcc"])
        .addArg(["--style", "json"])
        .addArg(["--level", "all"])
        .run;

    writelnUt(r.stdout);
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
        .addArg(["--mutant", "dcr"])
        .addArg(["--style", "csv"])
        .addArg(["--level", "all"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        `"ID","Kind","Description","Location","Comment"`,
        `"8","dcr","'var1_long_text >5' to 'true'","build/plugin/mutate/plugin_testdata/report_as_csv.cpp:7:9",""`,
        `"9","dcr","'var1_long_text >5' to 'false'","build/plugin/mutate/plugin_testdata/report_as_csv.cpp:7:9",""`,
        `"27","dcr","'case 2:`,
        `        return true;' to ''","build/plugin/mutate/plugin_testdata/report_as_csv.cpp:11:5",""`,
    ]).shouldBeIn(r.stdout);
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
        .addArg(["--section", "tc_stat"])
        .addArg(["--style", "plain"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "| Percentage | Count | TestCase |",
        "|------------|-------|----------|",
        "| 80         | 4     | tc_2     |",
        "| 40         | 2     | tc_3     |",
        "| 40         | 2     | tc_1     |",
    ]).shouldBeIn(r.stdout);
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
    ]).shouldBeIn(r.stdout);
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
        .addArg(["--section", "tc_stat"])
        .addArg(["--style", "plain"])
        .addArg(["--section-tc_stat-num", "2"])
        .addArg(["--section-tc_stat-sort", "bottom"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "| Percentage | Count | TestCase |",
        "|------------|-------|----------|",
        "| 40         | 2     | tc_1     |",
        "| 40         | 2     | tc_3     |",
    ]).shouldBeIn(r.stdout);
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
        ]).shouldBeIn(r.stdout);
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
        import dextool.plugin.mutate.backend.type : TestCase;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
        db.updateMutation(MutationId(1), Mutation.Status.alive, 5.dur!"msecs", null);

        auto r = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .addArg(["--mutant", "rorp"])
            .addArg("--diff-from-stdin")
            .setStdin(readText(programFile ~ ".diff"))
            .run;

        // Act
        testConsecutiveSparseOrder!SubStr(["warning:"]).shouldNotBeIn(r.stdout);
        testConsecutiveSparseOrder!SubStr(["warning:"]).shouldNotBeIn(r.stderr);
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
            auto m = db.getLineMetadata(fid, SourceLoc(line,0));
            m.attr.match!((NoMetadata a) {shouldBeFalse(true);},
                     (NoMut) {
                         m.id.shouldEqual(fid);
                         m.line.shouldEqual(line);
            });
        }
        foreach (line; [8,9])
            db.getLineMetadata(fid, SourceLoc(line,0)).isNoMut.shouldBeFalse;
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
            .addArg(["--section", "summary"])
            .addArg(["--style", "plain"])
            .run;

        auto markdown = makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "summary"])
            .addArg(["--style", "markdown"])
            .run;

        // TODO how to verify this? arsd.dom?
        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
            "Score:       0.808",
            "Total:       26",
            "Untested:    19",
            "Alive:       15",
            "Killed:      11",
            "Timeout:     0",
            "Killed by compiler: 0",
            "Suppressed (nomut): 10 (0.385",
        ]).shouldBeIn(plain.stdout);

        testConsecutiveSparseOrder!SubStr([
            "Score:       0.808",
            "Total:       26",
            "Untested:    19",
            "Alive:       15",
            "Killed:      11",
            "Timeout:     0",
            "Killed by compiler: 0",
            "Suppressed (nomut): 10 (0.385",
        ]).shouldBeIn(markdown.stdout);
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
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
            "Mutation Score <b>0.808</b>",
            "Total",
            "26",
            "Untested",
            "19",
            "Alive",
            "15",
            "Killed",
            "11",
            "Timeout",
            "0",
            "Killed by compiler",
            "0",
            "NoMut",
            "10",
            "NoMut/total",
            "0.385",
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
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

    testConsecutiveSparseOrder!SubStr([
        "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''","'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''",             "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''",
        "'meta' : 'nomut'", "'meta' : 'nomut'", "'meta' : 'nomut'", "'meta' : 'nomut'", "'meta' : 'nomut'", "'meta' : 'nomut'", "'meta' : 'nomut'", "'meta' : 'nomut'", "'meta' : 'nomut'",
        "'meta' : 'nomut'",
        "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''",
        "'meta' : 'nomut'",
        "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''", "'meta' : ''",
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
            .addArg(["--section", "summary"])
            .addArg(["--style", "html"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;

        // assert
        testConsecutiveSparseOrder!SubStr([
            `<h2>group1</h2>`,
            `<a href="files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html`,
            `<br`,
            `with comment`
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "nomut.html")).byLineCopy.array);

        // mutants should only be reported one time.
        testConsecutiveSparseOrder!SubStr([
            `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#28`,
            `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#28`,
            `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#29`,
            `files/build_plugin_mutate_plugin_testdata_report_nomut1.cpp.html#29`,
        ]).shouldNotBeIn(File(buildPath(testEnv.outdir.toString, "html", "nomut.html")).byLineCopy.array);
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
        db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [tc1,tc2,tc3]);
        db.updateMutation(MutationId(3), Mutation.Status.killed, 5.dur!"msecs", [tc1]);
        db.updateMutation(MutationId(8), Mutation.Status.killed, 5.dur!"msecs", [tc1,tc2]);
        db.updateMutation(MutationId(12), Mutation.Status.killed, 5.dur!"msecs", [tc1,tc2,tc3]);
        db.updateMutation(MutationId(15), Mutation.Status.killed, 5.dur!"msecs", [tc1,tc2]);

        // Act
        makeDextoolReport(testEnv, testData.dirName)
            .addArg(["--style", "html"])
            .addArg(["--section", "tc_similarity"])
            .addArg(["--logdir", testEnv.outdir.toString])
            .run;
        testConsecutiveSparseOrder!SubStr([
            `<h2 class="tbl_header"><i class="right"></i> tc_1</h2>`,
            `<td>tc_2</td>`,
            `<td>0.667</td>`,
            `<td>tc_3</td>`,
            `<td>0.333</td>`,
            `<h2 class="tbl_header"><i class="right"></i> tc_2</h2>`,
            `<td>tc_1</td>`,
            `<td>1.00</td>`,
            `<td>tc_3</td>`,
            `<td>0.500</td>`,
            `<h2 class="tbl_header"><i class="right"></i> tc_3</h2>`,
            `<td>tc_1</td>`,
            `<td>1.00</td>`,
            `<td>tc_2</td>`,
            `<td>1.00</td>`,
        ]).shouldBeIn(File(buildPath(testEnv.outdir.toString, "html", "test_case_similarity.html")).byLineCopy.array);
    }
}
