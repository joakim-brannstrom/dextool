// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
import scriptlike;
import utils;
import std.path : asAbsolutePath, asNormalizedPath;

int main(string[] args) {
    if (args.length <= 1) {
        writef("Usage: %s <path-to-dextool>\n", args[0]);
        return 1;
    }

    testEnv = TestEnv("outdir", "cpp_fail_log", args[1]);

    // Setup and cleanup
    chdir(thisExePath.dirName);
    scope (exit)
        testEnv.teardown();
    testEnv.setup();

    // start testing
    try {
        //stage1();
        //stage2();
        devTest();
    }
    catch (ErrorLevelException ex) {
        printStatus(Status.Fail, ex.msg);
        return 1;
    }

    return 0;
}
