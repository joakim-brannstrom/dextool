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

    const auto flags = compilerFlags();

    foreach (f; files) {
        auto input_ext = Path(f);
        scope (failure)
            testEnv.save(input_ext.baseName.toString);

        auto out_hdr = testEnv.outdir ~ "test_double.hpp";
        auto out_impl = testEnv.outdir ~ "test_double.cpp";
        auto out_gmock = testEnv.outdir ~ "test_double_gmock.hpp";

        printStatus(Status.Run, input_ext);
        auto params = ["cpptestdouble", "--gmock", "--debug"];
        auto incls = ["-I" ~ (root ~ "extra").absolutePath.toString];
        auto dex_flags = ["-xc++"] ~ incls;
        switch (input_ext.baseName.toString) {
        case "exclude_self.hpp":
            runDextool(input_ext,
                    params ~ ["--file-exclude=.*/" ~ input_ext.baseName.toString], dex_flags);
            break;
        case "param_restrict.hpp":
            runDextool(input_ext, params ~ ["--file-restrict=.*/" ~ input_ext.baseName.toString,
                    "--file-restrict=.*/b.hpp"], dex_flags);
            break;

        default:
            runDextool(input_ext, params, dex_flags);
        }

        println(Color.yellow, "Comparing");
        auto input = input_ext.stripExtension;
        compareResult(GR(input ~ Ext(".hpp.ref"), out_hdr),
                GR(input ~ Ext(".cpp.ref"), out_impl),
                GR(Path(input.toString ~ "_gmock.hpp.ref"), out_gmock));

        println(Color.yellow, "Compiling");
        auto mainf = Path("testdata/cpp/main_dev.cpp").absolutePath;
        incls ~= "-I" ~ input_ext.dirName.toString;
        switch (input_ext.baseName.toString) {
        default:
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE"], incls);
        }

        printStatus(Status.Ok, input_ext);
        testEnv.clean();
    }
}

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
