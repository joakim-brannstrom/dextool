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
