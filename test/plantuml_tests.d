// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module plantuml_tests;

import std.typecons : Flag, Yes, No;

import scriptlike;
import unit_threaded : Name, shouldEqual, ShouldFail;
import utils;

enum globalTestdir = "plantuml_tests";

struct TestParams {
    Flag!"skipCompare" skipCompare;

    Path root;
    Path input_ext;
    Path out_pu;

    // dextool parameters;
    string[] dexParams;
    string[] dexFlags;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/uml").absolutePath;
    p.input_ext = p.root ~ Path(f);

    p.out_pu = testEnv.outdir ~ "testdouble_component.pu";

    p.dexParams = ["--DRT-gcopt=profile:1", "uml", "--debug"];
    p.dexFlags = [];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv) {
    dextoolYap("Input:%s", p.input_ext.toRawString);
    runDextool(p.input_ext, testEnv, p.dexParams, p.dexFlags);

    if (!p.skipCompare) {
        dextoolYap("Comparing");
        auto input = p.input_ext.stripExtension;
        // dfmt off
        compareResult(
                      GR(input ~ Ext(".pu.ref"), p.out_pu),
                      );
        // dfmt on
    }
}

@Name("Should be a class diagram")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/single_class.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with 25 classes")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/multiple_class.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be two related classes by inheritance")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/inherit_class.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be two classes related by composition")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_member.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should skip the function pointer")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_skip_funcptr.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should skip the pointer")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_skip_ptr.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class in a namespace visualized with fully qualified name")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a lonely class even though instances exist in global and namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/global_instance.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should wrap relators in strings to correcty relate templates")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/compose_of_vector.hpp", testEnv);
    p.dexParams ~= ["--file-restrict='.*/'" ~ p.input_ext.baseName.toString];
    runTestFile(p, testEnv);
}
