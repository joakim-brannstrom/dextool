/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Test of the backend for the plugin plantuml.
*/
module test.component.plantuml;

import std.typecons : BlackHole;

import unit_threaded;
import test.clang_util;

import application.types;
import cpptooling.analyzer.kind : TypeKind;
import cpptooling.analyzer.clang.ast : ClangAST;
import cpptooling.analyzer.clang.context;
import cpptooling.data.symbol.container : Container;
import plugin.backend.plantuml;

alias BHController = BlackHole!Controller;
alias BHParameters = BlackHole!Parameters;

///
@safe class DummyController : BHController {
    override bool doFile(in string filename, in string info) {
        return true;
    }

    override FileName doComponentNameStrip(FileName fname) {
        import std.path : dirName, baseName;

        return FileName((cast(string) fname).dirName.baseName);
    }
}

///
pure const @safe class DummyParameters : BHParameters {
    override Flag!"genClassMethod" genClassMethod() {
        return cast(typeof(return)) true;
    }

    override Flag!"genClassParamDependency" genClassParamDependency() {
        return cast(typeof(return)) true;
    }

    override Flag!"genClassInheritDependency" genClassInheritDependency() {
        return cast(typeof(return)) true;
    }

    override Flag!"genClassMemberDependency" genClassMemberDependency() {
        return cast(typeof(return)) true;
    }
}

/** Emulate the data structures that the frontend uses to communicate with the
 * backend.
 */
class Backend {
    DummyController ctrl;
    DummyParameters params;
    UMLClassDiagram uml_class;
    UMLComponentDiagram uml_component;
    UMLVisitor!(Controller, TransformToDiagram!(Controller, Parameters)) visitor;

    Container container;
    TransformToDiagram!(Controller, Parameters) transform;
    ClangAST!(typeof(visitor)) ast;

    this() {
        ctrl = new DummyController;
        params = new DummyParameters;
        uml_class = new UMLClassDiagram;
        uml_component = new UMLComponentDiagram;

        transform = typeof(transform)(ctrl, params, (USRType usr) @safe{
            return container.find!TypeKind(usr);
        }, uml_component, uml_class);
        visitor = new typeof(visitor)(ctrl, transform, container);
    }
}

@DontTest class Fixture : TestCase {
    Backend be;

    override void setup() {
        be = new Backend;
    }
}

class TestParameterDependency : Fixture {
    enum comp_a = "
class A {
};";

    enum comp_ctor = "
class A;

class A_ByCtor {
    A_ByCtor(A* a);
};";

    // generated key
    enum comp_a_key = "Y29tcF9h";
    enum comp_ctor_key = "Y29tcF9jdG9y";

    override void test() {
        // arrange
        auto ctx0 = ClangContext.fromString!"/comp_a/a.hpp"(comp_a);
        auto ctx1 = ClangContext.fromString!"/comp_ctor/code.hpp"(comp_ctor);

        // act
        be.ast.root = ctx0.cursor;
        be.ast.accept(be.visitor);

        be.ast.root = ctx1.cursor;
        be.ast.accept(be.visitor);

        writelnUt(be.uml_component.toString);
        writelnUt(be.container.toString);

        // assert
        be.uml_component.asArray.length.shouldEqual(2);

        auto result = be.uml_component.relateToFlatArray;
        result.length.shouldEqual(1);

        result[0].from.shouldEqual(USRType(comp_ctor_key));
        result[0].to.shouldEqual(USRType(comp_a_key));
        result[0].kind.shouldEqual(RelateKind.Associate);
        result[0].count.shouldEqual(1);
    }
}
