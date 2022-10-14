/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_analyzer;

import std.file : copy;
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
        .addFlag("-std=c++11")
        .run;

    testAnyOrder!Re([
        `.*4.*dcrTrue`,
        `.*10.*dcrFalse`,
    ]).shouldBeIn(r.output);
}

@(testId ~ "shall detect changes in dependencies based on #include")
unittest {
    mixin(EnvSetup(globalTestdir));

    const programHdr = (testEnv.outdir ~ "program.hpp").toString;
    const programCpp = (testEnv.outdir ~ "program.cpp").toString;

    copy((testData ~ "analyze_dep.cpp").toString, programCpp);

    makeDextoolAnalyze(testEnv)
        .addInputArg(programCpp)
        .run;

    makeDextoolAnalyze(testEnv)
        .addInputArg(programCpp)
        .run;

    makeDextoolAnalyze(testEnv)
        .addInputArg(programCpp)
        .addFlag("-DIS_VERSION_TWO")
        .run;
}

@(testId ~ "shall transitively detect changes in dependencies")
unittest {
    import std.stdio : File;

    mixin(EnvSetup(globalTestdir));

    const programHdr = (testEnv.outdir ~ "program.hpp").toString;
    const programHdr2 = (testEnv.outdir ~ "program2.hpp").toString;
    const programCpp = (testEnv.outdir ~ "program.cpp").toString;

    copy((testData ~ "analyze_trans_dep.cpp").toString, programCpp);
    copy((testData ~ "analyze_trans_dep.hpp").toString, programHdr);
    copy((testData ~ "analyze_trans_dep2.hpp").toString, programHdr2);

    makeDextoolAnalyze(testEnv)
        .addInputArg(programCpp)
        .run;
}

@(testId ~ "shall find the mutants even though the SUT contains a compilation error")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto r = makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "analyze_compile_error.cpp")
        .addPostArg("--allow-errors")
        .run;

    testConsecutiveSparseOrder!Re(["info: Saving.*analyze_compile_error.cpp"]).shouldBeIn(r.output);
}

@(testId ~ "shall not drop mutants when analyzing with different -D")
unittest {
    mixin(EnvSetup(globalTestdir));

    copy((testData ~ "id_gen_algo/program.cpp").toString, (testEnv.outdir ~ "program.cpp").toString);
    copy((testData ~ "id_gen_algo/compile_commands.json").toString, (testEnv.outdir ~ "compile_commands.json").toString);

    auto r1 = makeDextoolAnalyze(testEnv)
        .addPostArg(["--compile-db", (testEnv.outdir ~ "compile_commands.json").toString])
        .addPostArg(["--id-algorithm", "relaxed"])
        .addPostArg(["--threads", "1"])
        .run;

    testConsecutiveSparseOrder!Re(["info: Removing orphaned.*"]).shouldBeIn(r1.output);
    testConsecutiveSparseOrder!Re(["info: Removing orphaned.*",
                                  "info: .*/.* removed.*"
    ]).shouldNotBeIn(r1.output);
}
