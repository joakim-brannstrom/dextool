/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module test the configuration functionality.
*/
module dextool_test.test_config;

import std.file : copy, exists;
import std.stdio : File;

import dextool_test.utility;
import dextool_test.fixtures;

@(testId ~ "shall read the config sections without errors")
unittest {
    mixin(EnvSetup(globalTestdir));

    immutable conf = (testEnv.outdir ~ ".dextool_mutate.toml").toString;

    copy((testData ~ "config/all_section.toml").toString, conf);
    File((testEnv.outdir ~ "compile_commands.json").toString, "w").write("[]");

    auto res = makeDextoolAnalyze(testEnv).addArg([
        "-c", (testEnv.outdir ~ ".dextool_mutate.toml").toString
    ]).addArg([
        "--compile-db", (testEnv.outdir ~ "compile_commands.json").toString
    ]).run;

    res.success.shouldBeTrue;
}

@(testId ~ "shall create a config file when called with --init from admin subcommand")
unittest {
    mixin(EnvSetup(globalTestdir));

    auto res = makeDextool(testEnv).setWorkdir(null).args(["mutate", "admin"])
        .postArg(["-c", (testEnv.outdir ~ "myconf.toml").toString]).addPostArg("--init").run;

    exists((testEnv.outdir ~ "myconf.toml").toString).shouldBeTrue;
}

@(testId ~ "shall read the test groups when reporting")
unittest {
    mixin(EnvSetup(globalTestdir));

    immutable conf = (testEnv.outdir ~ ".dextool_mutate.toml").toString;

    copy((testData ~ "config/read_test_groups.toml").toString, conf);
    File((testEnv.outdir ~ "compile_commands.json").toString, "w").write("[]");

    auto r = makeDextoolAnalyze(testEnv).addArg([
        "-c", (testEnv.outdir ~ ".dextool_mutate.toml").toString
    ]).addArg([
        "--compile-db", (testEnv.outdir ~ "compile_commands.json").toString
    ]).run;

    testConsecutiveSparseOrder!SubStr([
        "uc1, Parameterized Tests, Value.*|TypeTrait.*|Typed.*"
    ]).shouldBeIn(r.output);
    testConsecutiveSparseOrder!SubStr(
            ["uc2, Test Report, TestResult.*|TestPartResult.*|TestInfo.*"]).shouldBeIn(r.output);
    testConsecutiveSparseOrder!SubStr(["uc3, Resetting Mocks, VerifyAndClear.*"]).shouldBeIn(
            r.output);
}

@(testId ~ "shall use the user specified compiler to determine system includes")
unittest {
    import std.path : buildPath;

    mixin(EnvSetup(globalTestdir));
    dirContentCopy(buildPath(testData.toString, "config",
            "specify_sys_compiler"), testEnv.outdir.toString);
    File((testEnv.outdir ~ ".dextool_mutate.toml").toString, "a").writefln(
            `use_compiler_system_includes = "%s/fake_cc.d"`, testEnv.outdir.toString);

    auto r = makeDextoolAnalyze(testEnv).addArg([
        "-c", (testEnv.outdir ~ ".dextool_mutate.toml").toString
    ]).addArg([
        "--compile-db", (testEnv.outdir ~ "compile_commands.json").toString
    ]).run;

    testConsecutiveSparseOrder!SubStr([
        "trace: Compiler flags: -xc++ -isystem /foo/bar"
    ]).shouldBeIn(r.output);
}

// shall extend test commands with those in the specified directory when testing
class ExtendTestCommandsFromTestCmdDir : SimpleFixture {
    override void test() {
        import std.path : buildPath;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        immutable dextoolConf = buildPath(testEnv.outdir.toString, ".dextool_mutate.toml");
        copy(buildPath(testData.toString, "config", "test_cmd_dir.toml"), dextoolConf);
        File(dextoolConf, "a").writefln(`test_cmd_dir = %s
test_cmd_dir_flag = ["--foo"]`, [testEnv.outdir.toString]);

        makeDextoolAnalyze(testEnv).addInputArg(programFile).addPostArg([
            "-c", dextoolConf
        ]).run;

        // dfmt off
        auto r = dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(["--dry-run"])
            .addPostArg(["-c", dextoolConf])
            .addPostArg(["--mutant", "dcr"])
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--test-cmd", "/bin/true"])
            .addPostArg(["--build-cmd", compileScript])
            .addPostArg(["--test-cmd", testScript])
            .addPostArg(["--test-timeout", "10000"])
            .run;
        // dfmt on

        testConsecutiveSparseOrder!Re([
            `.*Found test commands in`, `.*/test.sh --foo`,
        ]).shouldBeIn(r.output);
        testConsecutiveSparseOrder!Re([
            `.*Found test commands in`, `.*/compile.sh --foo`,
        ]).shouldBeIn(r.output);
    }
}

class ReanalyzeOnConfigChange : SimpleFixture {
    override void test() {
        import std.path : buildPath;

        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        immutable dextoolConf = buildPath(testEnv.outdir.toString, ".dextool_mutate.toml");
        copy(buildPath(testData.toString, "config", "test_cmd_dir.toml"), dextoolConf);

        auto r0 = makeDextoolAnalyze(testEnv).addInputArg(programFile)
            .addPostArg(["-c", dextoolConf]).run;
        testConsecutiveSparseOrder!Re([".*Saving.*report_one_ror.*"]).shouldBeIn(r0.output);

        auto r1 = makeDextoolAnalyze(testEnv).addInputArg(programFile)
            .addPostArg(["-c", dextoolConf]).run;
        testConsecutiveSparseOrder!Re([".*Unchanged.*report_one_ror.*"]).shouldBeIn(r1.output);

        File(dextoolConf, "a").writeln;

        auto r2 = makeDextoolAnalyze(testEnv).addInputArg(programFile)
            .addPostArg(["-c", dextoolConf]).run;
        testConsecutiveSparseOrder!Re([".*Saving.*report_one_ror.*"]).shouldBeIn(r2.output);
    }
}
