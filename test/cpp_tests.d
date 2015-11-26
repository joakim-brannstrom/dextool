// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
import scriptlike;
import utils;
import std.path : asAbsolutePath, asNormalizedPath;

void devTest() {
    writeln("Develop Testing");
    auto root = Path("testdata/cpp/dev");
    auto files = dirEntries(root, "*.{hpp}", SpanMode.shallow);

    foreach (f; files) {
        auto input_ext = Path(f);
        auto out_hdr = Path(.OUTDIR ~ "/test_double.hpp");
        auto out_impl = Path(.OUTDIR ~ "/test_double.cpp");
        auto out_global = Path(.OUTDIR ~ "/test_double_global.cpp");
        auto out_gmock = Path(.OUTDIR ~ "/test_double_gmock.hpp");

        print(Color.yellow, "[ Run ] ", input_ext);
        auto params = ["cpptestdouble", "--gmock", "--debug"];
        auto flags = ["-xc++", "-I" ~ (root ~ "extra").toString];
        switch (input_ext.baseName.toString) {

        default:
            runDextool(input_ext, params, flags);
        }

        print(Color.yellow, "Comparing");

        print(Color.yellow, "Compiling");

        print(Color.green, "[  OK ] ", input_ext);

        pause("press enter to continue...");
        cleanTestEnv();
    }
}

int main(string[] args) {
    if (args.length <= 1) {
        writef("Usage: %s <path-to-dextool>\n", args[0]);
        return 1;
    }

    setOutdir("outdata");
    setDextool(args[1]);

    // Setup and cleanup
    chdir(thisExePath.dirName);
    scope (exit)
        teardownTestEnv();
    setupTestEnv();

    // start testing
    try {
        //stage1();
        //stage2();
        devTest();
    }
    catch (ErrorLevelException ex) {
        print(Color.red, ex.msg);
        pause();
        return 1;
    }

    return 0;
}
