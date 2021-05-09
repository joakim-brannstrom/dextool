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

class ShallRunAorSchema : SchemataFixutre {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "aor"]).run;

        // dfmt off
        testConsecutiveSparseOrder!SubStr([
                `from '+' to '-'`,
                `alive`,
                ]).shouldBeIn(r.output);

        testAnyOrder!SubStr(["failed to compile"]).shouldNotBeIn(r.output);
        // dfmt on
    }
}

class ShallUseSchemaSanityCheck : SchemataFixutre {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg([
                "--mutant", "aor", "--schema-check"
                ]).run;

        // dfmt off
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
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "uoi"]).run;

        // dfmt off
        testConsecutiveSparseOrder!SubStr([
                `from '!x' to '!!x'`,
                `alive`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}

class ShallRunLcrSchema : SchemataFixutre {
    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "lcr"]).run;

        // dfmt off
        testConsecutiveSparseOrder!SubStr([
                `from '&&' to '||'`,
                `alive`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}

// There is a problem in the clang AST wherein it sometimes is off-by-one when
// it comes to deleting lhs and/or rhs of binary operator.
class ShallRemoveParenthesisBalanced : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_bug_unbalanced_parenthesis.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "lcrb"]).run;

        // dfmt off
        testAnyOrder!SubStr([
                `from '(x & (x - 1)) |' to ''`,
                `from '| x' to ''`,
                `from 'x &' to ''`,
                `from '& (x - 1)' to ''`,
                `from '|' to '&'`,
                `from '&' to '|'`,
                ]).shouldBeIn(r.output);
        // dfmt on
    }
}

class ShallGenerateValidSchemaForOverload : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_op_overload.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addFlag("-std=c++11").run;

        auto r = runDextoolTest(testEnv).addPostArg([
                "--mutant", "sdl", "--mutant", "aor", "--mutant", "rorp"
                ]).addFlag("-std=c++11").run;

        testAnyOrder!SubStr([`*this`,]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '+'`,]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '=='`,]).shouldNotBeIn(r.output);
    }
}

class ShallGenerateValidSchemaForNestedIf : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_nested_if.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addFlag("-std=c++11").run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "sdl"]).run;

        testAnyOrder!SubStr([`*this`,]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '+'`,]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '=='`,]).shouldNotBeIn(r.output);
    }
}

class ShallGenerateValidSchemaForEnableIf : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_enableif.cpp").toString;
    }

    override string scriptBuild() {
        return "#!/bin/bash
set -e
g++ -std=c++14 %s -o %s
";
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addFlag("-std=c++14").run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "rorp"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaForPtr : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_aor.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addFlag("-std=c++11").run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "aor"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaForConstexpr : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_constexpr.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaForCallInReturn : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_return.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaClasses : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_classes.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaArraySub : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_array_subscript.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
        testAnyOrder!SubStr(["from '+' to '-'"]).shouldNotBeIn(r.output);
    }
}

class ShallGenerateValidSchemaWithLambda : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_lambda.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaWithStructBind : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_struct_bind.cpp").toString;
    }

    override string scriptBuild() {
        return "#!/bin/bash
set -e
g++ -std=c++17 -fsyntax-only -c %s -o %s
";
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addFlag("-std=c++17").run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaForSwitch : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_switch.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addPostArg([
                "--mutant", "all"
                ]).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaForBinOp : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_binop.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addPostArg([
                "--mutant", "all"
                ]).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaForTemplate : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_template.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addPostArg([
                "--mutant", "all"
                ]).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}

class ShallGenerateValidSchemaForTerneryOp : SchemataFixutre {
    override string programFile() {
        return (testData ~ "schemata_ternery.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addPostArg([
                "--mutant", "all"
                ]).run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "all"]).run;

        testAnyOrder!SubStr(["Skipping schema because it failed to compile"]).shouldNotBeIn(
                r.output);
    }
}
