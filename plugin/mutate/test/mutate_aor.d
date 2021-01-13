/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

#TST-mutation_aor
*/
module dextool_test.mutate_aor;

import std.algorithm;
import std.array;
import std.format : format;

import dextool_test.utility;
import dextool_test.fixtures;

const ops = ["+", "-", "*", "/", "%"];

@(testId ~ "shall produce all AOR operator mutations")
unittest {
    foreach (getValue; [
            "aor_primitive.cpp", "aor_primitive_modern_cpp.cpp",
            "aor_object_overload.cpp"
        ]) {
        mixin(envSetup(globalTestdir, No.setupEnv));
        testEnv.outputSuffix(getValue);
        testEnv.setupEnv;

        makeDextoolAnalyze(testEnv).addInputArg(testData ~ getValue).addFlag("-std=c++11").run;
        auto r = makeDextool(testEnv).addArg(["test"]).addArg([
                "--mutant", "aor"
                ]).run;

        testAnyOrder!SubStr(ops.map!(a => a)
                .permutations
                .filter!(a => a[0] != a[1])
                .map!(a => format!"from '%s' to '%s'"(a[0], a[1]))
                .array).shouldBeIn(r.output);
    }
}

@(testId ~ "shall produce all AORs operator mutations")
unittest {
    foreach (getValue; [
            "aor_primitive.cpp", "aor_primitive_modern_cpp.cpp",
            "aor_object_overload.cpp"
        ]) {
        mixin(envSetup(globalTestdir, No.setupEnv));
        testEnv.outputSuffix(getValue);
        testEnv.setupEnv;

        makeDextoolAnalyze(testEnv).addInputArg(testData ~ getValue).addFlag("-std=c++11").run;
        auto r = makeDextool(testEnv).addArg(["test"]).addArg([
                "--mutant", "aors"
                ]).run;

        testAnyOrder!SubStr([
                `from '+' to '-'`, `from '-' to '+'`, `from '/' to '*'`,
                `from '*' to '/'`, `from '%' to '/'`,
                ]).shouldBeIn(r.output);

        testAnyOrder!SubStr([`from '+' to '*'`]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '*' to '+'`]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '/' to '-'`]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '%' to '-'`]).shouldNotBeIn(r.output);
        testAnyOrder!SubStr([`from '-' to '*'`]).shouldNotBeIn(r.output);
    }
}

@(testId ~ "shall produce all AOR delete mutations")
@ShouldFail unittest {
    foreach (getValue; [
            "aor_primitive.cpp", "aor_object_overload.cpp",
            "aor_primitive_modern_cpp.cpp"
        ]) {
        mixin(envSetup(globalTestdir, No.setupEnv));
        testEnv.outputSuffix(getValue);
        testEnv.setupEnv;

        makeDextoolAnalyze(testEnv).addInputArg(testData ~ getValue).run;
        auto r = makeDextool(testEnv).addArg(["test"]).addArg([
                "--mutant", "aor"
                ]).run;

        testAnyOrder!SubStr(ops.map!(a => format!"from 'a %s' to ''"(a)).array).shouldBeIn(
                r.output);
    }
}

class ShallOnlyGenerateValidAorSchemas : SchemataFixutre {
    override string programFile() {
        return (testData ~ "aor_primitive_float.cpp").toString;
    }

    override void test() {
        mixin(EnvSetup(globalTestdir));
        precondition(testEnv);

        makeDextoolAnalyze(testEnv).addInputArg(programCode).addFlag("-std=c++11").run;

        auto r = runDextoolTest(testEnv).addPostArg(["--mutant", "aor"]).addFlag("-std=c++11").run;

        // modulo/reminder operator do not support floating point.
        testAnyOrder!SubStr(ops.map!(a => a)
                .permutations
                .filter!(a => a[0] != a[1])
                .filter!(a => a[0] != "%")
                .filter!(a => a[1] != "%")
                .map!(a => format!"from '%s' to '%s'"(a[0], a[1]))
                .array).shouldBeIn(r.output);
    }
}
