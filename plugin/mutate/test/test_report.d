/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-plugin_mutate_report_for_human

TODO the full test specification is not implemented.
*/
module dextool_test.test_report;

import dextool_test.utility;

// dfmt off

@("shall report the content in the database as human readable to stdout")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName).run;

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

@("shall report the ROR mutations in the database as gcc compiler warnings/notes with fixits to stderr")
unittest {
    auto input_src = testData ~ "report_one_ror_mutation_point.cpp";
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(input_src)
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "ror"])
        .addArg(["--report", "compiler"])
        .addArg(["--report-level", "all"])
        .run;

    testConsecutiveSparseOrder!SubStr([
                      ":6:11: warning: rorGE: replace '>' with '>='",
                      ":6:11: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{6:11-6:12}:">="`,
                      ":6:11: warning: rorNE: replace '>' with '!='",
                      ":6:11: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{6:11-6:12}:"!="`,
                      ":6:9: warning: rorFalse: replace 'x > 3' with 'false'",
                      ":6:9: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{6:9-6:14}:"false"`,
    ]).shouldBeIn(r.stderr);
}

@("shall report tool integration notes with the full text for dccTrue and dccBomb")
unittest {
    auto input_src = testData ~ "report_tool_integration.cpp";
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(input_src)
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "dcc"])
        .addArg(["--report", "compiler"])
        .addArg(["--report-level", "all"])
        .run;

    testConsecutiveSparseOrder!SubStr([
                      ":7:9: warning: dccTrue: replace 'var1_...' with 'true'",
                      ":7:9: note: status:unknown id:",
                      ":7:9: note: replace 'var1_long_text > 5'",
                      `fix-it:"` ~ input_src.toString ~ `":{7:9-7:27}:"true"`,
                      ":11:5: warning: dccBomb: replace 'retur...' with '*((ch...'",
                      ":11:5: note: status:unknown id:",
                      ":11:5: note: replace 'return true;'",
                      ":11:5: note: with '*((char*)0)='x';break;'",
                      `fix-it:"` ~ input_src.toString ~ `":{11:5-11:17}:"*((char*)0)='x';break;"`,
    ]).shouldBeIn(r.stderr);
}

@("shall append a line indicating that the file is mutated")
unittest {
    // TODO
}
