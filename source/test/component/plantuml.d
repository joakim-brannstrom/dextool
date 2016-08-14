/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Test of the backend for the plugin plantuml.
*/
module test.component.plantuml;

import std.format : format;
import std.typecons : BlackHole, Flag, Yes, No, scoped;

import unit_threaded;
import test.clang_util;

import clang.TranslationUnit : TranslationUnit;

import application.types;
import cpptooling.analyzer.kind : TypeKind;
import cpptooling.analyzer.type : USRType;
import cpptooling.analyzer.clang.ast : ClangAST;
import cpptooling.analyzer.clang.context;
import cpptooling.data.symbol.container : Container;
import cpptooling.utility.virtualfilesystem : FileName, Content;
import plugin.frontend.plantuml : Lookup;
import plugin.backend.plantuml;

private:

alias BHController = BlackHole!Controller;
alias BHParameters = BlackHole!Parameters;

/* These two lines are useful when debugging.
writelnUt(be.container.toString);
writelnUt(be.uml_component.toString);
*/

///
@safe class DummyController : BHController {
    import application.types : FileName;

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

    TransformToDiagram!(Controller, Parameters, Lookup) transform;
    UMLVisitor!(Controller, typeof(transform)) visitor;

    Container container;
    ClangAST!(typeof(visitor)) ast;
    ClangContext ctx;

    this() {
        ctrl = new DummyController;
        params = new DummyParameters;
        uml_class = new UMLClassDiagram;
        uml_component = new UMLComponentDiagram;

        transform = new typeof(transform)(ctrl, params, Lookup(&container),
                uml_component, uml_class);
        visitor = new typeof(visitor)(ctrl, transform, container);
        ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    }
}

// Test Cases ****************************************************************

// Begin. Test of parameter dependency for component diagrams.

void actTwoFiles(BackendT)(ref TranslationUnit tu0, ref TranslationUnit tu1, ref BackendT be)
        if (is(BackendT == typeof(scoped!Backend()))) {
    checkForCompilerErrors(tu0).shouldBeFalse;
    checkForCompilerErrors(tu1).shouldBeFalse;

    be.ast.root = tu0.cursor;
    be.ast.accept(be.visitor);

    be.ast.root = tu1.cursor;
    be.ast.accept(be.visitor);

    be.transform.finalize();
}

// Reusable code snippets
struct Snippet {
    enum includes = ["-I/"];
    enum include_comp_a = `#include "comp_a/a.hpp"`;
    enum comp_a = "
class A {
};";
}

// Generated component keys. See plugin.backend.plantuml.makeComponentKey
struct Key {
    enum comp_a = "Y29tcF9h";
    enum comp = "Y29tcA";
}

@Name("Should be a component dependency from comp->comp_a via a c'tors parameter")
@Values("", "*", "&")
unittest {
    // Testing that even though comp is processed first and have a forward
    // declaration of A a relation is still created to the definition of A

    enum comp_ctor = "
class A;

class A_ByCtor {
    A_ByCtor(A%s a);
};";

    // arrange
    auto be = scoped!Backend();
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp/ctor.hpp",
            cast(Content) format(comp_ctor, getValue!string));
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp_a/a.hpp", cast(Content) Snippet.comp_a);
    auto tu0 = be.ctx.makeTranslationUnit("/comp/ctor.hpp", Snippet.includes);
    auto tu1 = be.ctx.makeTranslationUnit("/comp_a/a.hpp", Snippet.includes);

    // act
    actTwoFiles(tu0, tu1, be);

    // assert
    auto result = be.uml_component.relateToFlatArray;
    result.length.shouldEqual(1);

    result[0].from.shouldEqual(USRType(Key.comp));
    result[0].to.shouldEqual(USRType(Key.comp_a));
}

@Name("Should be a component dependency from comp->comp_a via a methods parameter")
@Values("", "*", "&")
unittest {
    enum comp_method = "
class A;

class A_ByParam {
    void param(A%s a);
};";

    // arrange
    auto be = scoped!Backend();
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp/a.hpp",
            cast(Content) format(comp_method, getValue!string));
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp_a/a.hpp", cast(Content) Snippet.comp_a);
    auto tu0 = be.ctx.makeTranslationUnit("/comp/a.hpp", Snippet.includes);
    auto tu1 = be.ctx.makeTranslationUnit("/comp_a/a.hpp", Snippet.includes);

    // act
    actTwoFiles(tu0, tu1, be);

    // assert
    auto result = be.uml_component.relateToFlatArray;
    result.length.shouldEqual(1);

    result[0].from.shouldEqual(USRType(Key.comp));
    result[0].to.shouldEqual(USRType(Key.comp_a));
}

@Name("Should be a component dependency from comp->comp_a via a functions parameter")
@Values("", "*", "&")
unittest {
    enum comp_func = "
class A;

void free_func(A%s a);
";

    // arrange
    auto be = scoped!Backend();
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp/fun.hpp",
            cast(Content) format(comp_func, getValue!string));
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp_a/a.hpp", cast(Content) Snippet.comp_a);
    auto tu0 = be.ctx.makeTranslationUnit("/comp/fun.hpp", Snippet.includes);
    auto tu1 = be.ctx.makeTranslationUnit("/comp_a/a.hpp", Snippet.includes);

    // act
    actTwoFiles(tu0, tu1, be);

    // assert
    auto result = be.uml_component.relateToFlatArray;
    result.length.shouldEqual(1);

    result[0].from.shouldEqual(USRType(Key.comp));
    result[0].to.shouldEqual(USRType(Key.comp_a));
}

@Name("Should be a component dependency from comp->comp_a via a class member")
@Values("", "*", "&")
unittest {
    enum comp_func = "
%s
class A;

class A_ByMember {
    A%s a;
};";

    writelnUt(format(comp_func, getValue!string.length == 0 ? ""
            : Snippet.include_comp_a, getValue!string));

    // arrange
    auto be = scoped!Backend();
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp/fun.hpp",
            cast(Content) format(comp_func, getValue!string.length == 0
                ? Snippet.include_comp_a : "", getValue!string));
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp_a/a.hpp", cast(Content) Snippet.comp_a);
    auto tu0 = be.ctx.makeTranslationUnit("/comp/fun.hpp", Snippet.includes);
    auto tu1 = be.ctx.makeTranslationUnit("/comp_a/a.hpp", Snippet.includes);

    // act
    actTwoFiles(tu0, tu1, be);

    // assert
    auto result = be.uml_component.relateToFlatArray;
    result.length.shouldEqual(1);

    result[0].from.shouldEqual(USRType(Key.comp));
    result[0].to.shouldEqual(USRType(Key.comp_a));
}

@Name("Should be a component dependency from comp->comp_a via a free variable")
@Values("instantiation", "pointer")
unittest {
    enum comp_free_variable = "
class A;

A* a;
";

    enum comp_global_instantiation = `
#include "/comp_a/a.hpp"

A a;
`;

    string comp;

    switch (getValue!string) {
    case "instantiation":
        comp = comp_global_instantiation;
        break;
    case "pointer":
        comp = comp_free_variable;
        break;
    default:
        true.shouldBeFalse;
    }

    // arrange
    auto be = scoped!Backend();
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp/fun.hpp", cast(Content) comp);
    be.ctx.virtualFileSystem.put(cast(FileName) "/comp_a/a.hpp", cast(Content) Snippet.comp_a);
    auto tu0 = be.ctx.makeTranslationUnit("/comp/fun.hpp", Snippet.includes);
    auto tu1 = be.ctx.makeTranslationUnit("/comp_a/a.hpp", Snippet.includes);

    // act
    actTwoFiles(tu0, tu1, be);

    writelnUt(be.container.toString);
    writelnUt(be.uml_component.toString);

    // assert
    auto result = be.uml_component.relateToFlatArray;
    result.length.shouldEqual(1);

    result[0].from.shouldEqual(USRType(Key.comp));
    result[0].to.shouldEqual(USRType(Key.comp_a));
}
