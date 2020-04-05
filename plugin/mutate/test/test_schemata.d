/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_schemata;

import std.format : format;
import std.path : relativePath;

import dextool.plugin.mutate.backend.database.standalone : Database;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;
static import dextool.type;

import dextool_test.utility;
import dextool_test.fixtures;

class SchemataFixutre : SimpleFixture {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override string scriptBuild() {
        return "#!/bin/bash
set -e
g++ %s -o %s
";
    }

    override string scriptTest() {
        return format("#!/bin/bash
set -e
%s
", program_bin);
    }

    auto runDextoolTest(ref TestEnv testEnv, string[] args) {
        // dfmt off
        return dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(args)
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compile_script])
            .addPostArg(["--test-cmd", test_script])
            .addPostArg(["--test-timeout", "10000"])
            .addPostArg(["--only-schemata"])
            .addPostArg(["--use-schemata"])
            .addPostArg(["--log-schemata"])
            .run;
        // dfmt on
    }
}

class ShallRunAorSchema : SchemataFixutre {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = runDextoolTest(testEnv, ["--mutant", "aor"]);

        // verify that a AOR schemata has executed and saved the result
        testConsecutiveSparseOrder!SubStr([
                `from '+' to '-'`,
                `alive`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}

class ShallRunDccSchema : SchemataFixutre {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = runDextoolTest(testEnv, ["--mutant", "dcc"]);

        // verify that a AOR schemata has executed and saved the result
        testConsecutiveSparseOrder!SubStr([
                `from 'x < 10' to 'false'`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}

class ShallRunDcrSchema : SchemataFixutre {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = runDextoolTest(testEnv, ["--mutant", "dcr"]);

        // verify that a AOR schemata has executed and saved the result
        testConsecutiveSparseOrder!SubStr([
                `from 'x < 10' to 'false'`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}

class ShallUseSchemataSanityCheck : SchemataFixutre {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = runDextoolTest(testEnv, ["--mutant", "aor", "--check-schemata"]);

        testConsecutiveSparseOrder!SubStr([
            `Found schemata`,
            `Schema`,
            `Use schema`,
            `Compile schema`,
            `Ok`,
            `Sanity check`,
            `Ok`,
            ]).shouldBeIn(r.output);
        // dfmt on
    }
}

class ShallRunUoiSchema : SchemataFixutre {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = runDextoolTest(testEnv, ["--mutant", "uoi"]);

        // verify that a AOR schemata has executed and saved the result
        testConsecutiveSparseOrder!SubStr([
                `from '!' to ''`,
                `alive`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}

class ShallRunSdlSchema : SchemataFixutre {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(program_cpp).run;

        // dfmt off
        auto r = runDextoolTest(testEnv, ["--mutant", "sdl"]);

        // verify that a AOR schemata has executed and saved the result
        testConsecutiveSparseOrder!SubStr([
                //`from '' to ''`,
                `alive`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}
