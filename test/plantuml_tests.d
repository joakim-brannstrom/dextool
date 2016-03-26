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
    Path base_file_compare;
    Path out_pu;

    // dextool parameters;
    string[] dexParams;
    string[] dexClassDiagram;
    string[] dexFlags;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/uml").absolutePath;
    p.input_ext = p.root ~ Path(f);
    p.base_file_compare = p.input_ext.stripExtension;

    p.out_pu = testEnv.outdir ~ "view_classes.pu";

    p.dexParams = ["--DRT-gcopt=profile:1", "uml", "--debug"];
    p.dexClassDiagram = ["--class-paramdep", "--class-inheritdep", "--class-memberdep"];
    p.dexFlags = [];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv) {
    dextoolYap("Input:%s", p.input_ext.toRawString);
    runDextool(p.input_ext, testEnv, p.dexParams ~ p.dexClassDiagram, p.dexFlags);

    if (!p.skipCompare) {
        dextoolYap("Comparing");
        Path input = p.base_file_compare;
        // dfmt off
        compareResult(
                      GR(input ~ Ext(".pu.ref"), p.out_pu),
                      );
        // dfmt on
    }
}

@Name("Should be a class diagram with methods")
unittest {
    //TODO deprecated test, see CLI test of --class-method
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/single_class.hpp", testEnv);
    p.dexClassDiagram ~= "--class-method";
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with NO methods")
unittest {
    //TODO deprecated test, see CLI test of --class-method
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/single_class_no_methods.hpp", testEnv);
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

@Name("Should be relations via composition and aggregation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_relate.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should relate classes by parameter dependency")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/param_dependency.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should load compiler settings from compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("compile_db/single_file_main.hpp", testEnv);
    // find compilation flags by looking up how single_file_main.c was compiled
    p.dexParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/single_file_db.json").toString];
    runTestFile(p, testEnv);
}

@Name("Should process all files in the compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("compile_db/two_files.hpp", testEnv);
    p.input_ext = Path("");
    p.dexParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/two_file_db.json").toString];
    runTestFile(p, testEnv);
}

@Name("Should merge classes in namespaces when processing the compilation DB")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("compile_db/merge_nested_ns.hpp", testEnv);
    p.input_ext = Path("");
    p.dexParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/merge_nested_ns_db.json").toString];
    runTestFile(p, testEnv);
}

@Name("Should continue even though a compile error occured")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("compile_db/bad_code.hpp", testEnv);
    p.input_ext = Path("");
    p.dexParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/bad_code_db.json")
        .toString, "--skip-file-error"];
    runTestFile(p, testEnv);
}

@Name("Should not have parameter dependency on primitive types")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/param_primitive_types.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Test of CLI with no class parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("cli/cli_classes.hpp", testEnv);
    p.dexClassDiagram = [];
    p.base_file_compare = p.input_ext.up ~ "cli_none";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-method")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("cli/cli_classes.hpp", testEnv);
    p.dexClassDiagram = ["--class-method"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_method";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-paramdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("cli/cli_classes.hpp", testEnv);
    p.dexClassDiagram = ["--class-paramdep"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_param_dep";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-inheritdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("cli/cli_classes.hpp", testEnv);
    p.dexClassDiagram = ["--class-inheritdep"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_inherit_dep";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-memberdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("cli/cli_classes.hpp", testEnv);
    p.dexClassDiagram = ["--class-memberdep"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_member_dep";
    runTestFile(p, testEnv);
}
