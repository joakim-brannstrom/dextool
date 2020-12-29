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

        makeDextoolAnalyze(testEnv).addInputArg(programCode).run;

        auto r = runDextoolTest(testEnv).addPostArg([
                "--mutant", "aor", "--check-schemata"
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
                `from '!' to ''`,
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
