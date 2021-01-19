/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.integration;

import logger = std.experimental.logger;
import std.path : dirName, stripExtension, setExtension, baseName;
import std.typecons : Flag, Yes, No;

import unit_threaded : shouldBeTrue, shouldBeFalse;

import dextool_test.utils;
import dextool_test.types;

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

    p.root = Path("plugin_testdata/uml");
    p.input_ext = p.root ~ f;
    p.base_file_compare = p.input_ext.toString.stripExtension;

    p.out_pu = testEnv.outdir ~ "view_classes.pu";

    p.dexParams = ["uml", "--debug"];
    p.dexDiagramParams = [
        "--class-paramdep", "--class-inheritdep", "--class-memberdep"
    ];
    p.dexFlags = [];

    return p;
}

TestParams genTestComponentParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("plugin_testdata/uml");
    p.input_ext = p.root ~ f;
    p.base_file_compare = p.input_ext.toString.stripExtension;

    p.out_pu = testEnv.outdir ~ "view_components.pu";

    p.dexParams = ["uml", "--debug"];
    p.dexDiagramParams = [];
    p.dexFlags = [
        "-I" ~ (p.input_ext.dirName ~ "a").toString,
        "-I" ~ (p.input_ext.dirName ~ "b").toString
    ];

    return p;
}

/// Returns: the output (stdout) from dextool.
string runTestFile(const ref TestParams p, ref TestEnv testEnv,
        Flag!"sortLines" sortLines = Yes.sortLines) {
    logger.info("Input: ", p.input_ext);
    auto output = runDextool(p.input_ext, testEnv, p.dexParams ~ p.dexDiagramParams, p.dexFlags);

    if (!p.skipCompare) {
        logger.info("Comparing");
        Path input = p.base_file_compare;
        // dfmt off
        compareResult(sortLines, Yes.skipComments,
                      GR(input.toString.setExtension(".pu.ref").Path, p.out_pu),
                      );
        // dfmt on
    }

    return output;
}

// BEGIN Test of single file analyze of Class Diagrams #######################

@(testId ~ "Should use the field declaration as the name of the anonymous union")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/bug_anon_union.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should use the field declaration as the name of the anonymous enum")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/bug_anon_enum.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram with methods")
unittest {
    //TODO deprecated test, see CLI test of --class-method
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/single_class.hpp", testEnv);
    p.dexDiagramParams ~= "--class-method";
    runTestFile(p, testEnv);
}

@(
        testId
        ~ "Should be a class diagram with NO methods and no self reference via copy ctor and assignment")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/single_class_no_methods.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram with 25 classes")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/multiple_class.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram with two related classes by inheritance")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/inherit_class.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram two classes related by composition")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/class_member.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram, skip the function pointer")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/bug_skip_funcptr.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram, skip the pointer")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/bug_skip_ptr.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram with a pure interface class")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/pure_interface.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram with an abstract class")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/abstract_interface.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(
        testId
        ~ "Should be a class diagram with a class in a namespace visualized with fully qualified name")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/class_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(
        testId
        ~ "Should be a class diagram with a lonely class even though instances exist in global and namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/global_instance.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram with relations via composition and aggregation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/class_relate.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class diagram where classes are related by parameter dependency")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/param_dependency.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(
        testId
        ~ "Should be a class diagram with no parameter dependency because the parameters are of primitive types")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/param_primitive_types.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class related to another via a using type alias")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("dev/bug_using.hpp", testEnv);
    runTestFile(p, testEnv);
}

// END   Test of single file analyze of Class Diagrams #######################

// BEGIN Compilation Database Tests ##########################################

@(testId ~ "Should load compiler settings from compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("compile_db/single_file_main.hpp", testEnv);
    // find compilation flags by looking up how single_file_main.c was compiled
    p.dexDiagramParams ~= [
        "--compile-db=" ~ (p.root ~ "compile_db/single_file_db.json").toString
    ];
    runTestFile(p, testEnv);
}

@(testId ~ "Should process all files in the compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addArg([
            "--compile-db", (testData ~ "compile_db/two_file_db.json").toString
            ]).addArg([
            "--class-paramdep", "--class-inheritdep", "--class-memberdep"
            ]).run;
    compareResult(Yes.sortLines, Yes.skipComments,
            GR(testData ~ "compile_db/two_file_db.pu.ref", testEnv.outdir ~ "view_classes.pu"));
}

@(testId ~ "Should track the component relation between dirs even though it is forward declared classes refering via method dependency and the return value")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addArg([
            "--compile-db", (testData ~ "compile_db/multi_file_db.json").toString
            ]).run;
    compareResult(Yes.sortLines, Yes.skipComments,
            GR(testData ~ "compile_db/track_return_via_ptr_ref.pu.ref",
                testEnv.outdir ~ "view_components.pu"));
}

@(testId ~ "Should merge classes in namespaces when processing the compilation DB")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addArg([
            "--compile-db", (testData ~ "compile_db/merge_nested_ns_db.json").toString
            ]).addArg([
            "--class-paramdep", "--class-inheritdep", "--class-memberdep"
            ]).run;
    compareResult(Yes.sortLines, Yes.skipComments,
            GR(testData ~ "compile_db/merge_nested_ns.pu.ref", testEnv.outdir ~ "view_classes.pu"));
}

@(testId ~ "Should continue even though a compile error occured")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addArg([
            "--compile-db", (testData ~ "compile_db/bad_code_db.json").toString
            ]).addArg([
            "--class-paramdep", "--class-inheritdep", "--class-memberdep"
            ]).addArg("--skip-file-error").run;
    compareResult(Yes.sortLines, Yes.skipComments,
            GR(testData ~ "compile_db/bad_code.pu.ref", testEnv.outdir ~ "view_classes.pu"));
}

// END   Compilation Database Tests ##########################################

// BEGIN CLI Tests ###########################################################

@(testId ~ "Test of CLI with no class parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = [];
    p.base_file_compare = p.input_ext.dirName.Path ~ "cli_none";
    runTestFile(p, testEnv);
}

@(testId ~ "Test of CLI --class-method")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-method"];
    p.base_file_compare = p.input_ext.dirName.Path ~ "cli_class_method";
    runTestFile(p, testEnv);
}

@(testId ~ "Test of CLI --class-paramdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-paramdep"];
    p.base_file_compare = p.input_ext.dirName.Path ~ "cli_class_param_dep";
    runTestFile(p, testEnv);
}

@(testId ~ "Test of CLI --class-inheritdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-inheritdep"];
    p.base_file_compare = p.input_ext.dirName.Path ~ "cli_class_inherit_dep";
    runTestFile(p, testEnv);
}

@(testId ~ "Test of CLI --class-memberdep")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_classes.hpp", testEnv);
    p.dexDiagramParams = ["--class-memberdep"];
    p.base_file_compare = p.input_ext.dirName.Path ~ "cli_class_member_dep";
    runTestFile(p, testEnv);
}

@(testId ~ "Test of CLI --gen-style-incl")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestClassParams("cli/cli_gen_style_include.hpp", testEnv);
    p.dexDiagramParams ~= "--gen-style-incl";
    runTestFile(p, testEnv);

    import std.file : exists;

    exists((testEnv.outdir ~ "view_style.iuml").toString).shouldBeTrue;
    compareResult(Yes.sortLines, Yes.skipComments,
            GR(Path(p.base_file_compare.toString ~ "_style.pu.ref"),
                testEnv.outdir ~ "view_style.iuml"));
}

@(testId ~ "Test of CLI --comp-strip")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "cli/cli_comp_strip.hpp").addArg([
            "--comp-strip", "(.*)/strip_this"
            ]).addIncludeFlag(testData ~ "cli/strip_this")
        .addIncludeFlag(testData ~ "cli/keep_this").run;
    compareResult(Yes.sortLines, Yes.skipComments,
            GR(testData ~ "cli/cli_comp_strip.pu.ref", testEnv.outdir ~ "view_components.pu"));
}

@(testId ~ "Test of CLI --comp-strip using a regex with 'OR'")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "cli/cli_comp_strip_complex.hpp")
        .addArg(["--comp-strip", "(.*)/strip_this|(.*)/keep_this"])
        .addIncludeFlag(testData ~ "cli/strip_this").addIncludeFlag(testData ~ "cli/keep_this").run;
    compareResult(Yes.sortLines, Yes.skipComments,
            GR(testData ~ "cli/cli_comp_strip_complex.pu.ref", testEnv.outdir ~ "view_components.pu"));
}

@(testId ~ "Test of CLI --comp-by-file. Should be components created from filenames")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("cli/cli_comp_by_file.hpp", testEnv);
    p.dexDiagramParams ~= ["--comp-by-file"];
    p.dexFlags = [
        "-I" ~ (p.input_ext.dirName.Path ~ "strip_this").toString,
        "-I" ~ (p.input_ext.dirName.Path ~ "keep_this").toString
    ];
    runTestFile(p, testEnv);
}

@(testId ~ "Test of CLI --gen-dot, include directive")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("cli/cli_gen_dot_incl_dotfile.hpp", testEnv);
    p.dexDiagramParams ~= ["--gen-dot"];
    foreach (f; [
            ["cli_gen_doc_incl_dotfile_class_dot", "view_classes_dot.dot"],
            ["cli_gen_dot_incl_dotfile_class_neato", "view_classes_neato.dot"],
            [
                "cli_gen_dot_incl_dotfile_component_dot",
                "view_components_dot.dot"
            ],
            [
                "cli_gen_dot_incl_dotfile_component_neato",
                "view_components_neato.dot"
            ]
        ]) {
        p.base_file_compare = p.base_file_compare.dirName.Path ~ f[0];
        p.out_pu = testEnv.outdir ~ f[1].setExtension(".pu");
        runTestFile(p, testEnv);
    }
}

@(testId ~ "Test of CLI --gen-dot, class diagram")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("cli/cli_gen_dot_class.hpp", testEnv);
    p.dexDiagramParams ~= [
        "--gen-dot", "--class-memberdep", "--class-inheritdep", "--class-paramdep"
    ];
    p.base_file_compare = p.base_file_compare.dirName.Path ~ "cli_gen_dot_class_dot";
    p.out_pu = testEnv.outdir ~ "view_classes_dot.dot";
    runTestFile(p, testEnv);
    p.base_file_compare = p.base_file_compare.dirName.Path ~ "cli_gen_dot_class_neato";
    p.out_pu = testEnv.outdir ~ "view_classes_neato.dot";
    runTestFile(p, testEnv);
}

@(testId ~ "Test of CLI --gen-dot, component diagram")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("cli/cli_gen_dot_component.hpp", testEnv);
    p.dexDiagramParams ~= [
        "--gen-dot", "--class-memberdep", "--class-inheritdep", "--class-paramdep"
    ];
    p.base_file_compare = p.base_file_compare.dirName.Path ~ "cli_gen_dot_component_dot";
    p.out_pu = testEnv.outdir ~ "view_components_dot.dot";
    runTestFile(p, testEnv);
    p.base_file_compare = p.base_file_compare.dirName.Path ~ "cli_gen_dot_component_neato";
    p.out_pu = testEnv.outdir ~ "view_components_neato.dot";
    runTestFile(p, testEnv);
}

// END   CLI Tests ###########################################################

// BEGIN Test Component Diagrams #############################################

@(testId ~ "Should analyse __sighandler_t")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("dev/bug_crash_on_sigset.hpp", testEnv);
    p.skipCompare = Yes.skipCompare;
    auto output = runTestFile(p, testEnv);

    output.sliceContains("$100").shouldBeFalse;
    output.sliceContains(`as include`).shouldBeTrue;
    output.sliceContains(`as bits`).shouldBeTrue;
}

@(testId ~ "Should always be able to backtrack")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("dev/bug_crash_on_sigset.hpp", testEnv);
    p.skipCompare = Yes.skipCompare;
    auto output = runTestFile(p, testEnv);

    output.sliceContains("$100").shouldBeFalse;
}

@(testId ~ "Should be a component diagram of two component related by class members")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_member.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a component diagram with two components related by class inheritance")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_inherit.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a component diagram with two components related by method parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_method.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be two components with no relation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/class_no_relation.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be two components related by a free function using a class as parameter")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/free_global_func.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be two components related by a free function in a namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/free_func_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be two components related by the type used to declare a global variable")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/global_var.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(
        testId
        ~ "Should be two components related by the type used to declare a variable enclosed in an namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestComponentParams("component/global_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

// END   Test Component Diagrams #############################################

auto makeDextool(const ref TestEnv env) {
    return dextool_test.makeDextool(env).setWorkdir(env.outdir).args(["uml"]);
}

Path testData() {
    return Path("plugin_testdata/uml");
}
