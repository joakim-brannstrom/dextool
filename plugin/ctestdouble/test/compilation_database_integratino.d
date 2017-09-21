/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.compilation_database_integration;

import dextool_test.utility;

// dfmt off

@(testId ~ "Should load compiler settings from compilation database")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "compile_db/single_file_main.c")
        .addArg(["--compile-db", (testData ~ "compile_db/single_file_db.json").toString])
        .addArg("--file-restrict=.*/single_file.h")
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .outputToDefaultBinary
        .addInclude(testData ~ "compile_db/dir1")
        .addDefine("DEXTOOL_TEST")
        .addArg(testData ~ "compile_db/single_file_main.cpp")
        .run;
    makeCommand(testEnv, defaultBinary).run;
}

@(testId ~ "Should fail with an error message when file not found in the compilation database")
unittest {
    mixin(envSetup(globalTestdir));
    auto r = makeDextool(testEnv)
        .throwOnExitStatus(false)
        .addInputArg(testData ~ "compile_db/file_not_found.c")
        .addArg(["--compile-db", (testData ~ "compile_db/single_file_db.json").toString])
        .run;

    r.success.shouldBeFalse;
    r.stderr.sliceContains("error: Unable to find any compiler flags for").shouldBeTrue;
}

@(testId ~ "shall derive the flags for parsing single_file.h via the #include in single_file_main.c in the compilation database")
@(Values(["compile_db/dir1/single_file.h", "use_file"], ["compile_db/single_file.h", "fallback"]))
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    testEnv.outputSuffix(getValue!(string[])[1]);
    testEnv.setupEnv;

    auto r = makeDextool(testEnv)
        .addArg(["--compile-db", (testData ~ "compile_db/single_file_db.json").toString])
        .addInputArg(testData ~ getValue!(string[])[0])
        .run;

    r.stderr.sliceContains("error: Unable to find any compiler flags for").shouldBeFalse;
    // the file returned shall be the full path for the one searching for
    r.stderr.sliceContains("because it has an '#include' for '" ~ (testData ~ "compile_db/dir1/single_file.h").toString).shouldBeTrue;
}

@(testId ~ "Should load compiler settings from the second compilation database")
unittest {
    mixin(envSetup(globalTestdir));
    TestParams p;
    p.root = Path("testdata/compile_db").absolutePath;
    p.input_ext = p.root ~ Path("file2.h");
    p.out_hdr = testEnv.outdir ~ "test_double.hpp";

    // find compilation flags by looking up how single_file_main.c was compiled
    p.dexParams = ["ctestdouble", "--debug", "--compile-db=" ~ (p.root ~ "db1.json")
        .toString, "--compile-db=" ~ (p.root ~ "db2.json").toString];

    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

@(testId ~ "Should use the exact supplied --in=... as key when looking in compile db")
unittest {
    mixin(envSetup(globalTestdir));
    TestParams p;
    p.root = Path("testdata/compile_db").absolutePath;
    p.input_ext = p.root ~ Path("file2.h");
    p.out_hdr = testEnv.outdir ~ "test_double.hpp";

    p.dexParams = ["ctestdouble", "--debug",
        "--compile-db=" ~ (p.root ~ "db2.json").toString, "--in=file2.h"];

    p.skipCompile = Yes.skipCompile;
    p.skipCompare = Yes.skipCompare;
    runTestFile(p, testEnv);
}
