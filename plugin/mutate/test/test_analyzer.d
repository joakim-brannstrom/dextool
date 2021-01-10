/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_analyzer;

import std.path : relativePath, buildPath;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;
static import dextool.type;

import dextool_test.utility;

// dfmt off

@(testId ~ "shall analyze the provided file")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "all_kinds_of_abs_mutation_points.cpp")
        .run;
}

@(testId ~ "shall exclude files from the analysis they are part of an excluded directory tree when analysing")
unittest {
    mixin(EnvSetup(globalTestdir));

    const programFile1 = testData ~ "analyze/file1.cpp";
    const programFile2 = testData ~ "analyze/exclude/file2.cpp";

    makeDextoolAnalyze(testEnv)
        .addInputArg(programFile1)
        .addInputArg(programFile2)
        .addPostArg(["--file-include", buildPath(testData.toString, "analyze/*")])
        .addPostArg(["--file-exclude", buildPath(testData.toString, "analyze/exclude/*")])
        .run;

    // assert
    auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

    const file1 = dextool.type.Path(relativePath(programFile1.toString, workDir.toString));
    const file2 = dextool.type.Path(relativePath(programFile2.toString, workDir.toString));

    db.getFileId(file1).isNull.shouldBeFalse;
    db.getFileId(file2).isNull.shouldBeTrue;
}

@(testId ~ "shall analyze the provided file and use fast database storage")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "all_kinds_of_abs_mutation_points.cpp")
        .run;
}

@(testId ~ "shall drop the undesired mutants when analyzing")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto r = makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "undesired_mutants.cpp")
        .addPostArg(["--mutant", "all"])
        .addFlag("-std=c++11")
        .run;

    testAnyOrder!Re([
        `trace:.*Dropping undesired mutant.*dcrTrue`,
        `trace:.*Dropping undesired mutant.*dcrFalse`,
        `trace:.*Dropping undesired mutant.*dcrReturnTrue`,
        `trace:.*Dropping undesired mutant.*dcrReturnFalse`,
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall save specified mutants when analyzing")
unittest {
    mixin(EnvSetup(globalTestdir));
    dextool_test.makeDextool(testEnv)
        .setWorkdir(workDir)
        .args(["mutate", "analyze"])
        .addArg(["--mutant", "lcr"])
        .addArg(["--profile"])
        .addArg(["--db", (testEnv.outdir ~ defaultDb).toString])
        .addArg(["--fast-db-store"])
        .addInputArg(testData ~ "all_kinds_of_abs_mutation_points.cpp")
        .addArg(["--fast-db-store"])
        .addFlag("-std=c++11")
        .run;

    auto r = makeDextoolReport(testEnv, testData ~ "all_kinds_of_abs_mutation_points.cpp")
        .addPostArg(["--mutant", "abs"])
        .run;

    testConsecutiveSparseOrder!Re([
        `Mutation operators: abs`,
        `Total:\s*0`,
    ]).shouldBeIn(r.output);
}
