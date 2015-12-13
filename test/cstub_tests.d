// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
import scriptlike;
import utils;
import std.path : asAbsolutePath, asNormalizedPath;

void stage1() {
    writeln("Stage 1");

    auto root = Path("testdata/cstub/stage_1");
    auto files = dirEntries(root, "*.{h,hpp}", SpanMode.shallow);

    foreach (f; files) {
        auto input_ext = Path(f);
        auto out_hdr = Path(.OUTDIR ~ "/test_double.hpp");
        auto out_impl = Path(.OUTDIR ~ "/test_double.cpp");
        auto out_global = Path(.OUTDIR ~ "/test_double_global.cpp");
        auto out_gmock = Path(.OUTDIR ~ "/test_double_gmock.hpp");

        print(Color.yellow, "[ Run ] ", input_ext);
        auto params = ["ctestdouble", "--debug"];
        switch (input_ext.baseName.toString) {
        case "class_func.hpp":
            runDextool(input_ext, params, ["-xc++", "-DAND_A_DEFINE"]);
            break;
        case "param_main.h":
            runDextool(input_ext, params ~ ["--main=Stub", "--main-fname=stub"], []);
            out_hdr = out_hdr.up ~ "stub.hpp";
            out_impl = out_impl.up ~ "stub.cpp";
            break;
        case "test_include_stdlib.hpp":
            runDextool(input_ext, params, ["-nostdinc"]);
            break;
        case "param_gmock.h":
            runDextool(input_ext, params ~ ["--gmock"], ["-nostdinc"]);
            break;

        default:
            runDextool(input_ext, params, []);
        }

        print(Color.yellow, "Comparing");
        auto input = input_ext.stripExtension;
        compareResult(GR(input ~ Ext(".hpp.ref"), out_hdr),
            GR(input ~ Ext(".cpp.ref"), out_impl),
            GR(Path(input.toString ~ "_global.cpp.ref"), out_global),
            GR(Path(input.toString ~ "_gmock.hpp.ref"), out_gmock));

        print(Color.yellow, "Compiling");
        auto flags = ["-std=c++03", "-Wpedantic", "-Werror"];
        auto incls = ["-I" ~ input_ext.dirName.toString];
        auto mainf = Path("testdata/cstub/main1.cpp");
        switch (input_ext.baseName.toString) {
        case "param_gmock.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_FUNC_PTR"],
                incls);
            break;
        case "param_main.h":
            compileResult(out_impl, mainf, flags, incls);
            break;
        case "variables.h":
            compileResult(out_impl, mainf, flags, incls);
            break;
        case "const.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_CONST"],
                incls);
            break;
        case "function_pointers.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_FUNC_PTR"],
                incls);
            break;
        case "arrays.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_ARRAY"],
                incls);
            break;

        default:
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE"], incls);
        }

        print(Color.green, "[  OK ] ", input_ext);
        cleanTestEnv();
    }
}

void stage2() {
    writeln("Stage 2");

    auto root = Path("testdata/cstub/stage_2");
    auto files = dirEntries(root, "*.{h,hpp}", SpanMode.shallow);

    foreach (f; files) {
        auto input_ext = Path(f);
        auto out_hdr = Path(.OUTDIR ~ "/test_double.hpp");
        auto out_impl = Path(.OUTDIR ~ "/test_double.cpp");
        auto out_global = Path(.OUTDIR ~ "/test_double_global.cpp");
        auto out_gmock = Path(.OUTDIR ~ "/test_double_gmock.hpp");

        print(Color.yellow, "[ Run ] ", input_ext);
        auto params = ["ctestdouble", "--debug"];
        auto incls = ["-I" ~ (root ~ "include").toString];
        switch (input_ext.baseName.toString) {
        case "no_overwrite.h":
            copy(root ~ "no_overwrite_pre_includes.hpp",
                Path(OUTDIR) ~ "test_double_pre_includes.hpp");
            copy(root ~ "no_overwrite_post_includes.hpp",
                Path(OUTDIR) ~ "test_double_post_includes.hpp");
            runDextool(input_ext, params ~ ["--gen-pre-incl",
                "--gen-post-incl"], incls ~ ["-DPRE_INCLUDES"]);
            break;
        case "no_overwrite_post_includes.hpp":
        case "no_overwrite_pre_includes.hpp":
            continue;

        case "param_exclude_many_files.h":
            runDextool(input_ext,
                params ~ ["--file-exclude=.*/" ~ input_ext.baseName.toString,
                `--file-exclude='.*/include/b\.[h,c]'`], incls);
            break;
        case "param_exclude_match_all.h":
            runDextool(input_ext,
                params ~ ["--file-exclude=.*/param_exclude_match_all.*",
                `--file-exclude='.*/include/b\.c'`], incls);
            break;
        case "param_exclude_one_file.h":
            runDextool(input_ext,
                params ~ ["--file-exclude=.*/" ~ input_ext.baseName.toString], incls);
            break;
        case "param_gen_pre_post_include.h":
            runDextool(input_ext, params ~ ["--gen-pre-incl", "--gen-post-incl"], incls);
            break;
        case "param_include.h":
            runDextool(input_ext, params ~ ["--td-include=b.h", "--td-include=stdio.h"],
                incls);
            break;
        case "param_restrict.h":
            runDextool(input_ext,
                params ~ ["--file-restrict=.*/" ~ input_ext.baseName.toString,
                "--file-restrict=.*/include/b.h"], incls);
            break;

        default:
            runDextool(input_ext, params, incls);
        }

        print(Color.yellow, "Comparing");
        auto input = input_ext.stripExtension;
        switch (input_ext.baseName.toString) {
        case "no_overwrite.h":
            compareResult(GR(input.up ~ "no_overwrite_pre_includes.hpp",
                Path(OUTDIR) ~ "test_double_pre_includes.hpp"),
                GR(input.up ~ "no_overwrite_post_includes.hpp",
                Path(OUTDIR) ~ "test_double_post_includes.hpp"));
            break;
        case "param_gen_pre_post_include.h":
            compareResult(GR(input ~ Ext(".hpp.ref"), out_hdr),
                GR(input ~ Ext(".cpp.ref"), out_impl),
                GR(input.up ~ "param_gen_pre_includes.hpp.ref",
                Path(OUTDIR) ~ "test_double_pre_includes.hpp"),
                GR(input.up ~ "param_gen_post_includes.hpp.ref",
                Path(OUTDIR) ~ "test_double_post_includes.hpp"));
            break;

        default:
            compareResult(GR(input ~ Ext(".hpp.ref"), out_hdr),
                GR(input ~ Ext(".cpp.ref"), out_impl),
                GR(Path(input.toString ~ "_global.cpp.ref"), out_global),
                GR(Path(input.toString ~ "_gmock.hpp.ref"), out_gmock));
        }

        print(Color.yellow, "Compiling");
        auto flags = ["-std=c++03", "-Wpedantic", "-Werror"];
        auto mainf = Path("testdata/cstub/main1.cpp");
        incls ~= "-I" ~ input_ext.dirName.toString;
        switch (input_ext.baseName.toString) {
        default:
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE"], incls);
        }

        print(Color.green, "[  OK ] ", input_ext);
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
        stage1();
        stage2();
    }
    catch (ErrorLevelException ex) {
        print(Color.red, ex.msg);
        pause();
        return 1;
    }

    return 0;
}
