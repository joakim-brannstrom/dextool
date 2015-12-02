// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
import scriptlike;
import utils;

void helperDemangleLog() {
    auto log = Path("trace.demangle.log");

    if (!exists(log)) {
        writeln("No log to demangle");
        return;
    }

    demangleProfileLog(log);
    pause("Profile at " ~ log.toString ~ ". Press enter to continue");
}

void profileGTest() {
    writeln("Performance profile: ctestdouble of GoogleTest");

    auto root = Path("testdata/stage_4/fused_gtest");
    auto input_ext = root ~ Path("gtest/gtest-all.cc");

    print(Color.yellow, "[ Run ] ", input_ext);
    auto params = ["ctestdouble", "--gen-pre-incl", "--gen-post-incl"];
    auto flags = ["-xc++", "-I" ~ root.toString];
    runDextool(input_ext, params, flags);

    print(Color.green, "[  OK ] ", input_ext);

    helperDemangleLog();
    cleanTestEnv();
}

int main(string[] args) {
    if (args.length <= 1) {
        writefln("Usage: %s <path-to-dextool>", args[0]);
        writeln("Must be a binary that produces trace.log. For example dextool-profile");
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
        profileGTest();
    }
    catch (ErrorLevelException ex) {
        print(Color.red, ex.msg);
        pause();
        return 1;
    }

    return 0;
}
