/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module graphml_tests;

import std.typecons : Flag, Yes, No;

import scriptlike;
import unit_threaded : Name, shouldEqual, ShouldFail, shouldBeTrue,
    shouldBeFalse;
import utils;

enum globalTestdir = "graphml_tests";

/** Make a hash out of the raw data.
 *
 * Copied from the implementation
 * import cpptooling.utility.hash : makeHash;
 */
size_t makeHash(T)(T raw) @safe pure nothrow @nogc {
    import std.digest.crc;

    size_t value = 0;

    if (raw is null)
        return value;
    ubyte[4] hash = crc32Of(raw);
    return value ^ ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
}

struct TestParams {
    Flag!"skipCompare" skipCompare;

    Path root;
    Path input_ext;
    Path out_xml;

    // dextool parameters;
    string[] dexParams;
    string[] dexDiagramParams;
    string[] dexFlags;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/graphml").absolutePath;
    p.input_ext = p.root ~ Path(f);

    p.out_xml = testEnv.outdir ~ "dextool_raw.graphml";

    p.dexParams = ["--DRT-gcopt=profile:1", "graphml", "--debug"];
    p.dexDiagramParams = ["--class-paramdep", "--class-inheritdep", "--class-memberdep"];
    p.dexFlags = [];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv) {
    dextoolYap("Input:%s", p.input_ext.toRawString);
    runDextool(p.input_ext, testEnv, p.dexParams ~ p.dexDiagramParams, p.dexFlags);
}

auto getDocument(T)(ref T p) {
    import std.xml;

    static import std.file;
    import std.utf : validate;
    import std.xml : Document, check;

    string fin = cast(string) std.file.read(p.out_xml.toString);
    validate(fin);
    check(fin);
    auto xml = new Document(fin);

    return xml;
}

struct Key {
    enum Kind {
        any,
        source,
        target
    }

    string id;
    Kind kind;

    this(string id) {
        this.id = id;
        this.kind = Kind.any;
    }

    this(string id, Kind kind) {
        this.id = id;
        this.kind = kind;
    }
}

auto getGraph(T)(T p) {
    return getDocument(p).elements.filter!(a => a.tag.name == "graph").front;
}

auto getNode(T)(T graph, string id) {
    auto id_ = makeHash(id).to!string;
    return graph.elements.filter!(a => a.tag.name == "node" && a.tag.attr["id"].text == id_);
}

auto getNodes(T)(T graph) {
    return graph.elements.filter!(a => a.tag.name == "node");
}

auto getNodeGraph(T)(T graph) {
    return graph.elements.filter!(a => a.tag.name == "graph");
}

auto countNode(T)(T graph, string id) {
    return graph.getNode(id).count;
}

auto getEdge(T)(T graph, string source, string target) {
    auto src_id = makeHash(source).to!string;
    auto target_id = makeHash(target).to!string;
    return graph.elements.filter!(a => a.tag.name == "edge"
            && a.tag.attr["source"].text == src_id && a.tag.attr["target"].text == target_id);
}

auto getEdgeSource(T)(T graph, string source) {
    auto src_id = makeHash(source).to!string;
    return graph.elements.filter!(a => a.tag.name == "edge" && a.tag.attr["source"].text == src_id);
}

auto getEdgeTarget(T)(T graph, string target) {
    auto target_id = makeHash(target).to!string;
    return graph.elements.filter!(a => a.tag.name == "edge" && a.tag.attr["target"].text
            == target_id);
}

auto countEdge(T)(T graph, string source, string target) {
    return graph.getEdge(source, target).map!(a => 1).count;
}

// BEGIN Testing #############################################################

@(testId ~ "Should be analyse data of a class in global namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_empty.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a class in a namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be analyse data of free functions in global namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("functions.h", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);
    string fid = "c:@F@func_return_func_ptr";

    // test the relation via the return type
    // function exist
    graph.countNode(fid).shouldEqual(1);
    // function relate to return type
    graph.countEdge(fid, "c:functions.h@T@gun_ptr").shouldEqual(1);
}

@(
        testId
        ~ "Should be analyze data of free variables in the global namespace related to the file they are declared in")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("variables.h", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    string fid = thisExePath.dirName.toString ~ "/testdata/graphml/variables.h";

    // Nodes for all globals exist.
    graph.countNode("c:@expect_primitive").shouldEqual(1);
    graph.countNode("c:@expect_primitive_array").shouldEqual(1);
    graph.countNode("c:@expect_const_primitive_array").shouldEqual(1);
    graph.countNode("c:@expect_b").shouldEqual(1);
    graph.countNode("c:@expect_c").shouldEqual(1);
    graph.countNode("c:@expect_d").shouldEqual(1);
    graph.countNode("c:@expect_e").shouldEqual(1);
    graph.countNode("c:@expect_f").shouldEqual(1);
    graph.countNode("c:@expect_g").shouldEqual(1);
    graph.countNode("c:@expect_h").shouldEqual(1);
    graph.countNode("c:@expect_i").shouldEqual(1);
    graph.countNode("c:@expect_my_int").shouldEqual(1);
    graph.countNode("c:@expect_const_my_int").shouldEqual(1);

    // the file should be related to all of them
    graph.countEdge(fid, "c:@expect_primitive").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_primitive_array").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_const_primitive_array").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_b").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_c").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_d").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_e").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_f").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_g").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_h").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_i").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_my_int").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_const_my_int").shouldEqual(1);

    // a ptr at a primitive do not result in an edge to the type
    graph.countEdge("c:@expect_d", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:23 Column:13$1expect_d").shouldEqual(0);

    // a ptr at e.g. a typedef of a primitive type result in an edge to the type
    graph.countEdge("c:@expect_const_ptr_my_int", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:36 Column:28§1expect_const_ptr_my_int").shouldEqual(
            1);
}

@(testId ~ "Should be free variables in a namespace and thus related to the namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("variables_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    immutable fid = "ns";

    // Nodes for all globals exist.
    graph.countNode("c:@N@ns@expect_primitive").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_primitive_array").shouldEqual(1);
    graph.countNode("c:variables.h@N@ns@expect_const_primitive_array").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_b").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_c").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_d").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_e").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_f").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_g").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_h").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_i").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_my_int").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_const_my_int").shouldEqual(1);

    // the file should be related to all of them
    graph.countEdge(fid, "c:@N@ns@expect_primitive").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_primitive_array").shouldEqual(1);
    graph.countEdge(fid, "c:variables.h@N@ns@expect_const_primitive_array").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_b").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_c").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_d").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_e").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_f").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_g").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_h").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_i").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_my_int").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_const_my_int").shouldEqual(1);

    // a ptr at a primitive do not result in an edge to the type
    graph.countEdge("c:@N@ns@expect_d", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:23 Column:13$1expect_d").shouldEqual(0);

    // a ptr at e.g. a typedef of a primitive type result in an edge to the type
    graph.countEdge("c:@N@ns@expect_const_ptr_my_int", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:36 Column:28§1expect_const_ptr_my_int").shouldEqual(
            1);
}

@(testId ~ "Should be all type of class classifications")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_variants_interface.hpp", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be all kind of member relations between classes")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_members.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // test forward declarations
    graph.countNode("c:@S@ToForward").shouldEqual(1);
    graph.countNode("c:@S@Forward_ptr").shouldEqual(1);
    graph.countNode("c:@S@Forward_ref").shouldEqual(1);
    graph.countNode("c:@S@Forward_decl").shouldEqual(1);

    graph.countEdge("c:@S@ToForward@FI@fwd_ptr", "c:@S@Forward_ptr").shouldEqual(1);
    graph.countEdge("c:@S@ToForward@FI@fwd_ref", "c:@S@Forward_ref").shouldEqual(1);
    graph.countEdge("c:@S@ToForward@FI@fwd_decl", "c:@S@Forward_decl").shouldEqual(1);

    // test definitions
    graph.countNode("c:@S@Impl").shouldEqual(1);
    graph.countNode("c:@S@Impl_ptr").shouldEqual(1);
    graph.countNode("c:@S@Impl_ref").shouldEqual(1);
    graph.countNode("c:@S@ToImpl").shouldEqual(1);
    graph.countEdge("c:@S@ToImpl@FI@impl", "c:@S@Impl").shouldEqual(1);
    graph.countEdge("c:@S@ToImpl@FI@impl_ref", "c:@S@Impl_ref").shouldEqual(1);
    graph.countEdge("c:@S@ToImpl@FI@impl_ptr", "c:@S@Impl_ptr").shouldEqual(1);

    // test that an edge to a primitive type is not formed
    graph.countNode("c:@S@ToPrimitive").shouldEqual(1);
    // dfmt off
    graph.elements
        // all edges from the node
        .filter!(a => a.tag.name == "edge" && a.tag.attr["source"].text == makeHash("c:@S@ToPrimitive").to!string())
        .count
        .shouldEqual(0);
    // dfmt on

    // test that a node and edge to a funcptr is formed
    string fid = "File:" ~ thisExePath.dirName.toString ~ "/testdata/graphml/class_members.hpp";
    graph.countNode("c:@S@ToFuncPtr").shouldEqual(1);
    graph.countEdge("c:@S@ToFuncPtr@FI@__foo", fid ~ " Line:44 Column:12§1__foo").shouldEqual(1);
}

@(testId ~ "Should be an inheritance representation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_inherit.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // test inherit depth of 2
    // VirtC -> VirtB -> VirtA
    graph.countNode("c:@S@VirtA").shouldEqual(1);
    graph.countNode("c:@S@VirtB").shouldEqual(1);
    graph.countNode("c:@S@VirtC").shouldEqual(1);

    graph.countEdge("c:@S@VirtB", "c:@S@VirtA").shouldEqual(1);
    graph.countEdge("c:@S@VirtC", "c:@S@VirtB").shouldEqual(1);

    // test multiple inheritance
    // Dup inherit from DupA and DupB
    graph.countNode("c:@S@Dup").shouldEqual(1);
    graph.countNode("c:@S@DupA").shouldEqual(1);
    graph.countNode("c:@S@DupB").shouldEqual(1);

    graph.countEdge("c:@S@Dup", "c:@S@DupA").shouldEqual(1);
    graph.countEdge("c:@S@Dup", "c:@S@DupB").shouldEqual(1);
}

@(testId ~ "Should be a class with methods represented and relations to method parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_methods.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // test that usage of a type in a method parameter result in a relation
    graph.countEdge("c:@S@Methods@F@func4#d#1d#&1d#1**1d#",
            "c:class_methods.hpp@T@MadeUp").shouldEqual(1);
    graph.countEdge("c:@S@Virtual@F@func4#d#1d#&1d#1**1d#",
            "c:class_methods.hpp@T@MadeUp").shouldEqual(1);
}

@(testId ~ "Should be callgraph between functions")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("functions_body_call.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);
    string id_empty = "c:@F@empty#";
    string id_single_call = "c:@F@single_call#";
    string id_for = "c:@F@for_#";
    string id_if = "c:@F@if_#";
    string id_nested = "c:@F@nested#";
    string id_arg0 = "c:@F@arg0#I#";
    string id_arg1 = "c:@F@arg1#I#";
    string id_self_ref = "c:@F@self_reference#I#";

    graph.countNode(id_empty).shouldEqual(1);
    graph.countEdge(id_single_call, id_empty).shouldEqual(1);
    graph.countEdge(id_for, id_empty).shouldEqual(1);
    graph.countEdge(id_if, id_empty).shouldEqual(1);
    graph.countEdge(id_if, id_arg0).shouldEqual(1);
    graph.countEdge(id_nested, id_arg0).shouldEqual(1);
    graph.countEdge(id_nested, id_arg1).shouldEqual(1);
    // no self referencing
    graph.countEdge(id_self_ref, id_self_ref).shouldEqual(0);
}

@(testId ~ "Should be functions related to globals")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("functions_body_globals.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);
    string id_global = "c:@global";

    graph.countEdge("c:@F@read_access#", id_global).shouldEqual(1);
    graph.countEdge("c:@F@assign_access#", id_global).shouldEqual(1);
}

@(testId ~ "Should be methods call chain")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_method_body.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    { // verify dependency of method on member
        auto g = graph.getNode("c:@S@CallOtherClass").front;
        auto ng = g.getNodeGraph.front;
        // class data contained in the group
        ng.countNode("c:@S@CallOtherClass@F@func#").shouldEqual(1);
        ng.countNode("c:@S@CallOtherClass@FI@a").shouldEqual(1);
        // dependency from member method to the member variable
        graph.countEdge("c:@S@CallOtherClass@F@func#", "c:@S@CallOtherClass@FI@a").shouldEqual(1);
        // dependency between member methods
        graph.countEdge("c:@S@CallOtherClass@F@func#", "c:@S@Dummy@F@fun#").shouldEqual(1);
    }

    { // verify no self referencing
        auto g = graph.getNode("c:@S@CallSelf").front;
        auto ng = g.getNodeGraph.front;
        // self referencing
        ng.countNode("c:@S@CallSelf@F@self#*1C#S0_#").shouldEqual(1);
        graph.countEdge("c:@S@CallSelf@F@self#*1C#S0_#",
                "c:@S@CallSelf@F@self#*1C#S0_#").shouldEqual(0);
    }

    // method using only primitive types have no outgoing edges
    graph.getEdgeSource("c:@S@MethodVariables@F@simple#I#").count.shouldEqual(0);

    // method only related to the type used in the body
    //graph.countEdge("c:@S@MethodVariables@F@use_typedef#I#",
    //        "c:class_method_body.hpp@S@MethodVariables@T@myInt").shouldEqual(1);

    // method with locals of ptr type to primitive types have no outgoing edges
    graph.getEdgeSource("c:@S@MethodVariables@F@ptr#I#").count.shouldEqual(0);

    // method with locals of ptr type to a reference primitive types have no
    // outgoing edges
    graph.getEdgeSource("c:@S@MethodVariables@F@ptr_ref#I#").count.shouldEqual(0);

    // method with locals of ptr type to a reference typedef type have one
    // outgoing edges, to the typedef
    //graph.getEdgeSource("c:@S@MethodVariables@F@ptr_ref_typedef#I#").count.shouldEqual(1);
    //graph.countEdge("c:@S@MethodVariables@F@ptr_ref_typedef#I#",
    //        "c:class_method_body.hpp@S@MethodVariable@T@myInt").shouldEqual(1);

    // method using a builtin should both result in an edge to the builtin and
    // a node for the builtin
    graph.countNode("c:@F@__builtin_huge_valf").shouldEqual(1);
    graph.countEdge("c:@S@MethodVariables@F@my_builtin#",
            "c:@F@__builtin_huge_valf").shouldEqual(1);

    { // method should be related to the field of the anonymosu union
        auto g = graph.getNode("c:@S@MethodVariables@Ua").front;
        auto ng = g.getNodeGraph.front;
        // two nodes in the anonymous struct should exist
        ng.countNode("c:@S@MethodVariables@Ua@FI@union_buf").shouldEqual(1);
        ng.countNode("c:@S@MethodVariables@Ua@FI@size").shouldEqual(1);
        // and then be related from the method to the specific field
        graph.countEdge("c:@S@MethodVariables@F@use_field_from_union#",
                "c:@S@MethodVariables@Ua@FI@union_buf").shouldEqual(1);
    }
}

@(testId ~ "Should be a typedef from inside the template")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("template.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // should look for the node below and then investigate that it contains
    auto n = graph.getNode("c:@N@std@S@char_traits>#C");
    n.save.count.shouldEqual(1);
    auto ng = n.front.getNodeGraph.front;

    // contains
    ng.countNode("c:@N@std@S@char_traits>#C@F@assign#&C#&1C#S").shouldEqual(1);
}

@("Should be a full representation of a C structs")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("structs.h", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // implicitly test that there are at least one node with this ID.
    auto d = graph.getNode("c:@SA@D").front;
    auto dg = d.getNodeGraph.front;

    dg.countNode("c:@SA@D@FI@x").shouldEqual(1);
    dg.countNode("c:@SA@D@FI@y").shouldEqual(1);
}
