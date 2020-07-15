/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.compilation_database_integration;

import std.path : buildPath;
import std.typecons : No, Yes;

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
    r.output.sliceContains("error: Unable to find any compiler flags for").shouldBeTrue;
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

    r.output.sliceContains(`Analyzing all files in the compilation DB for one that has an '#include "single_file.h"'`).shouldBeTrue;
    // the file returned shall be the full path for the one searching for
    r.output.sliceContains("because it has an '#include' for '" ~ (testData ~ "compile_db/dir1/single_file.h").toString).shouldBeTrue;
}

@(testId ~ "Should load compiler settings from the second compilation database")
unittest {
    mixin(envSetup(globalTestdir));
    auto r = makeDextool(testEnv)
        .addArg(["--compile-db", "testdata/compile_db/db1.json"])
        .addArg(["--compile-db", "testdata/compile_db/db2.json"])
        // find compilation flags by looking up how single_file_main.c was compiled
        .addInputArg("file2.h")
        .run;
}

@(testId ~ "Should use the exact supplied --in=... as key when looking in compile db")
unittest {
    mixin(envSetup(globalTestdir));
    auto r = makeDextool(testEnv)
        .addArg(["--compile-db", "testdata/compile_db/db1.json"])
        .addArg(["--compile-db", "testdata/compile_db/db2.json"])
        .addInputArg("testdata/compile_db/file2.h".Path)
        .run;
}
