/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-report_for_human

TODO the full test specification is not implemented.
*/
module dextool_test.test_report;

import core.time : dur;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;

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
        "Untested:",
        "Alive:",
        "Killed:",
        "Timeout:",
        "Total:"
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
        "| 100        | 1     | `>`  | `>=` |",
        "## Summary",
        "Mutation execution time:         5 ms",
        "Untested:",
        "Alive:",
        "Killed:",
        "Timeout:",
        "Total:"
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
                      `fix-it:"` ~ input_src.toString ~ `":{11:5-11:17}:"*((char*)0)='x';break;"`,
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
        `        return true;' to '/*case 2:`,
        `        return true;*/'","build/plugin/mutate/plugin_testdata/report_as_csv.cpp:11:5",""`,
    ]).shouldBeIn(r.stdout);
}

@(testId ~ "shall report test cases with how many mutants killed correctly counting the sum of mutants to as two")
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
    db.updateMutation(MutationId(2), Mutation.Status.killed, 10.dur!"msecs", [TestCase("tc_2"), TestCase("tc_3")]);
    db.updateMutation(MutationId(3), Mutation.Status.alive, 10.dur!"msecs", null);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "tc_stat"])
        .addArg(["--style", "plain"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "| Percentage | Count | TestCase | Location |",
        "|------------|-------|----------|----------|",
        "| 66.6667    | 2     | tc_2     |          |",
        "| 33.3333    | 1     | tc_3     |          |",
        "| 33.3333    | 1     | tc_1     |          |",
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
    db.updateMutation(MutationId(3), Mutation.Status.alive, 10.dur!"msecs", [TestCase("tc_3")]);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "tc_full_overlap"])
        .addArg(["--style", "plain"])
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
    db.updateMutation(MutationId(2), Mutation.Status.killed, 10.dur!"msecs", [TestCase("tc_2"), TestCase("tc_3")]);
    db.updateMutation(MutationId(3), Mutation.Status.alive, 10.dur!"msecs", null);

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
        "| 33.3333    | 1     | tc_1     |",
        "| 33.3333    | 1     | tc_3     |",
    ]).shouldBeIn(r.stdout);
}

@(testId ~ "shall report test cases that has killed zero mutants")
unittest {
    // regression that the count of mutations are the total are correct (killed+timeout+alive)
    import dextool.plugin.mutate.backend.type : TestCase;

    mixin(EnvSetup(globalTestdir));
    // Arrange
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;
    auto db = Database.make((testEnv.outdir ~ defaultDb).toString);
    db.setDetectedTestCases([TestCase("tc_1"), TestCase("tc_2"), TestCase("tc_3"), TestCase("tc_4")]);
    db.updateMutation(MutationId(1), Mutation.Status.killed, 5.dur!"msecs", [TestCase("tc_1"), TestCase("tc_2")]);
    db.updateMutation(MutationId(2), Mutation.Status.killed, 10.dur!"msecs", [TestCase("tc_2"), TestCase("tc_3")]);

    // Act
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--section", "tc_killed_no_mutants"])
        .addArg(["--style", "plain"])
        .run;

    testConsecutiveSparseOrder!SubStr([
        "| TestCase |",
        "|----------|",
        "| tc_4     |",
    ]).shouldBeIn(r.stdout);
}
