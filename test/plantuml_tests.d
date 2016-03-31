// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module plantuml_tests;

import std.typecons : Flag, Yes, No;

import scriptlike;
import unit_threaded : Name, shouldEqual, ShouldFail, shouldBeTrue;
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
    string[] dexDiagramParams;
    string[] dexFlags;
}

TestParams genTestClassParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/uml").absolutePath;
    p.input_ext = p.root ~ Path(f);
    p.base_file_compare = p.input_ext.stripExtension;

    p.out_pu = testEnv.outdir ~ "view_classes.pu";

    p.dexParams = ["--DRT-gcopt=profile:1", "uml", "--debug"];
    p.dexDiagramParams = ["--class-paramdep", "--class-inheritdep", "--class-memberdep"];
    p.dexFlags = [];

    return p;
}

TestParams genTestComponentParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/uml").absolutePath;
    p.input_ext = p.root ~ Path(f);
    p.base_file_compare = p.input_ext.stripExtension;

    p.out_pu = testEnv.outdir ~ "view_components.pu";

    p.dexParams = ["--DRT-gcopt=profile:1", "uml", "--debug"];
    p.dexDiagramParams = [];
    p.dexFlags = ["-I" ~ (p.input_ext.dirName ~ Path("a")).toString,
        "-I" ~ (p.input_ext.dirName ~ Path("b")).toString];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv) {
    dextoolYap("Input:%s", p.input_ext.toRawString);
    runDextool(p.input_ext, testEnv, p.dexParams ~ p.dexDiagramParams, p.dexFlags);

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

// BEGIN Test of single file analyze of Class Diagrams #######################

@Name("Should be a class diagram with methods")
unittest {
    //TODO deprecated test, see CLI test of --class-method
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/single_class.hpp", testEnv);
    p.dexDiagramParams ~= "--class-method";
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with NO methods")
unittest {
    //TODO deprecated test, see CLI test of --class-method
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/single_class_no_methods.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with 25 classes")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/multiple_class.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with two related classes by inheritance")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/inherit_class.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram two classes related by composition")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/class_member.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram, skip the function pointer")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/bug_skip_funcptr.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram, skip the pointer")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/bug_skip_ptr.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with a pure interface class")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/pure_interface.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with an abstract class")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/abstract_interface.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with a class in a namespace visualized with fully qualified name")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/class_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name(
        "Should be a class diagram with a lonely class even though instances exist in global and namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/global_instance.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name(
        "Should be a class diagram where the relators are wrapped in strings to correcty relate templates")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/compose_of_vector.hpp", testEnv);
    p.dexDiagramParams ~= ["--file-restrict='.*/'" ~ p.input_ext.baseName.toString];
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram with relations via composition and aggregation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/class_relate.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a class diagram where classes are related by parameter dependency")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/param_dependency.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name(
        "Should be a class diagram with no parameter dependency because the parameters are of primitive types")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/param_primitive_types.hpp", testEnv);
    runTestFile(p, testEnv);
}

// END   Test of single file analyze of Class Diagrams #######################

// BEGIN Compilation Database Tests ##########################################

@Name("Should load compiler settings from compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("compile_db/single_file_main.hpp", testEnv);
    // find compilation flags by looking up how single_file_main.c was compiled
    p.dexDiagramParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/single_file_db.json").toString];
    runTestFile(p, testEnv);
}

@Name("Should process all files in the compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("compile_db/two_files.hpp", testEnv);
    p.input_ext = Path("");
    p.dexDiagramParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/two_file_db.json").toString];
    runTestFile(p, testEnv);
}

@Name("Should merge classes in namespaces when processing the compilation DB")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("compile_db/merge_nested_ns.hpp", testEnv);
    p.input_ext = Path("");
    p.dexDiagramParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/merge_nested_ns_db.json")
        .toString];
    runTestFile(p, testEnv);
}

@Name("Should continue even though a compile error occured")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("compile_db/bad_code.hpp", testEnv);
    p.input_ext = Path("");
    p.dexDiagramParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/bad_code_db.json")
        .toString, "--skip-file-error"];
    runTestFile(p, testEnv);
}

// END   Compilation Database Tests ##########################################

// BEGIN CLI Tests ###########################################################

@Name("Test of CLI with no class parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = [];
    p.base_file_compare = p.input_ext.up ~ "cli_none";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-method")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-method"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_method";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-paramdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-paramdep"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_param_dep";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-inheritdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-inheritdep"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_inherit_dep";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --class-memberdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-memberdep"];
    p.base_file_compare = p.input_ext.up ~ "cli_class_member_dep";
    runTestFile(p, testEnv);
}

@Name("Test of CLI --gen-style-incl")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_gen_style_include.hpp", testEnv);
    p.dexDiagramParams ~= "--gen-style-incl";
    runTestFile(p, testEnv);

    import std.file : exists;

    exists((testEnv.outdir ~ "view_style.iuml").toString).shouldBeTrue;
}

@Name("Test of CLI --comp-strip")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("cli/cli_comp_strip.hpp", testEnv);
    p.dexDiagramParams ~= "--comp-strip='(.*)/strip_this'";
    p.dexFlags = ["-I" ~ (p.input_ext.dirName ~ Path("strip_this")).toString,
        "-I" ~ (p.input_ext.dirName ~ Path("keep_this")).toString];
    runTestFile(p, testEnv);
}

@Name("Test of CLI --comp-strip with 'OR' strip regex")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("cli/cli_comp_strip_complex.hpp", testEnv);
    p.dexDiagramParams ~= "--comp-strip='(.*)/strip_this|(.*)/keep_this'";
    p.dexFlags = ["-I" ~ (p.input_ext.dirName ~ Path("strip_this")).toString,
        "-I" ~ (p.input_ext.dirName ~ Path("keep_this")).toString];
    runTestFile(p, testEnv);
}

// END   CLI Tests ###########################################################

// BEGIN Test Component Diagrams #############################################

@Name("Should be a component diagram of two component related by class members")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_member.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a component diagram with two components related by class inheritance")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_inherit.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be a component diagram with two components related by method parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_method.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be two components with no relation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_no_relation.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be two components related by a free function using a class as parameter")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/free_global_func.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be two components related by a free function in a namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/free_func_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be two components related by the type used to declare a global variable")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/global_var.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name(
        "Should be two components related by the type used to declare a variable enclosed in an namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/global_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

// END   Test Component Diagrams #############################################
