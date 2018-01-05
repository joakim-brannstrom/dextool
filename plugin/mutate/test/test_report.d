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
    makeDextool(testEnv)
        .addInputArg(testData ~ "report_one_ror_mutation_point.cpp")
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextool(testEnv).addArg(["--mode", "report"]).run;

    makeSubSeq!SubStr([
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
    makeDextool(testEnv)
        .addInputArg(input_src)
        .addArg(["--mode", "analyzer"])
        .run;
    auto r = makeDextoolReport(testEnv, testData.dirName)
        .addArg(["--mutant", "ror"])
        .addArg(["--report", "compiler"])
        .addArg(["--report-level", "all"])
        .run;

    makeSubSeq!SubStr([
                      ":2:11: warning: rorGE: replace ‘>’ with ‘>=’",
                      ":2:11: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{2:11-2:12}:">="`,
                      ":2:11: warning: rorNE: replace ‘>’ with ‘!=’",
                      ":2:11: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{2:11-2:12}:"!="`,
                      ":2:9: warning: rorFalse: replace ‘x > 3’ with ‘false’",
                      ":2:9: note: status:unknown id:",
                      `fix-it:"` ~ input_src.toString ~ `":{2:9-2:14}:"false"`,
    ]).shouldBeIn(r.stderr);
}
