// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsrcgen.plantuml;

import std.meta : AliasSeq, staticIndexOf;
import std.typecons : Flag, Yes, No;

import dsrcgen.base;

version (Have_unit_threaded) {
    import unit_threaded : Name, shouldEqual;
} else {
    struct Name {
        string n;
    }

    void shouldEqual(T0, T1)(T0 value, T1 expect) {
        assert(value == expect, value);
    }
}

@safe:

class Comment : BaseModule {
    mixin Attrs;

    private string contents;
    this(string contents) {
        this.contents = contents;
    }

    override string renderIndent(int parent_level, int level) {
        if ("begin" in attrs) {
            return indent(attrs["begin"] ~ contents, parent_level, level);
        }

        return indent("' " ~ contents, parent_level, level);
    }
}

enum Relate {
    WeakRelate,
    Relate,
    Compose,
    Aggregate,
    Extend,
    ArrowTo,
    AggregateArrowTo,
    DotArrowTo
}

string relateToString(Relate relate) {
    string r_type;
    final switch (relate) with (Relate) {
    case WeakRelate:
        r_type = "..";
        break;
    case Relate:
        r_type = "--";
        break;
    case Compose:
        r_type = "o--";
        break;
    case Aggregate:
        r_type = "*--";
        break;
    case Extend:
        r_type = "--|>";
        break;
    case ArrowTo:
        r_type = "-->";
        break;
    case AggregateArrowTo:
        r_type = "*-->";
        break;
    case DotArrowTo:
        r_type = "->";
        break;
    }

    return r_type;
}

enum LabelPos {
    Left,
    Right,
    OnRelation
}

import std.traits : ReturnType;
import std.typecons : Typedef, Tuple;

alias ClassModuleType = Typedef!(PlantumlModule, null, "ClassModuleType");
alias ClassAsType = Typedef!(Text!PlantumlModule, null, "ComponentAsType");
alias ClassSpotType = Typedef!(PlantumlModule, null, "ClassSpotType");
alias ClassNameType = Typedef!(string, string.init, "ClassNameType");
alias ClassType = Tuple!(ClassNameType, "name", ClassModuleType, "m",
        ClassSpotType, "spot", ClassAsType, "as");

alias ComponentModuleType = Typedef!(PlantumlModule, null, "ComponentModuleType");
alias ComponentAsType = Typedef!(Text!PlantumlModule, null, "ComponentAsType");
alias ComponentNameType = Typedef!(string, string.init, "ComponentNameType");
alias ComponentType = Tuple!(ComponentNameType, "name", ComponentModuleType,
        "m", ComponentAsType, "as");

alias RelationType = Typedef!(ReturnType!(PlantumlModule.stmt),
        ReturnType!(PlantumlModule.stmt).init, "RelationType");

mixin template RelateTypes(Tleft, Tright, Trel, Tblock) {
    alias RelateLeft = Typedef!(Tleft, Tleft.init, "RelateLeft");
    alias RelateRight = Typedef!(Tright, Tright.init, "RelateRight");
    alias RelateMiddle = Typedef!(Trel, Trel.init, "RelateMiddle");
    alias RelateBlock = Typedef!(Tblock, Tblock.init, "RelationBlock");
    alias Relation = Tuple!(RelateLeft, "left", RelateRight, "right",
            RelateMiddle, "rel", RelateBlock, "block");
}

mixin RelateTypes!(Text!PlantumlModule, Text!PlantumlModule,
        Text!PlantumlModule, PlantumlModule);

// Types that can be related between each other
alias CanRelateSeq = AliasSeq!(ClassNameType, ComponentNameType);
enum CanRelate(T) = staticIndexOf!(T, CanRelateSeq) >= 0;

class PlantumlModule : BaseModule {
    mixin Attrs;

    auto comment(string comment) {
        auto e = new Comment(comment);
        e.sep;
        append(e);
        return e;
    }

    auto text(string content) {
        auto e = new Text!(typeof(this))(content);
        append(e);
        return e;
    }

    auto base() {
        auto e = new typeof(this);
        append(e);
        return e;
    }

    // Statements
    Stmt stmt(string stmt_, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Stmt(stmt_);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    ClassType class_(string name) {
        import std.format : format;

        auto e = stmt(format(`class "%s"`, name));
        auto as = e.text("");
        auto spot = as.text("");

        return ClassType(ClassNameType(name), ClassModuleType(e),
                ClassSpotType(spot), ClassAsType(as));
    }

    ClassType classBody(string name) {
        import std.format : format;

        auto e = stmt(format(`class "%s"`, name));
        auto as = e.text("");
        auto spot = as.text("");

        e.text(" {");
        e.sep;
        auto s = e.base;
        s.suppressIndent(1);
        e.stmt("}", No.addSep).suppressThisIndent(1);

        return ClassType(ClassNameType(name), ClassModuleType(s),
                ClassSpotType(spot), ClassAsType(as));
    }

    auto component(string name) {
        import std.format : format;

        auto e = stmt(format(`component "%s"`, name));
        auto as = e.text("");

        return ComponentType(ComponentNameType(name), ComponentModuleType(e), ComponentAsType(as));
    }

    auto componentBody(string name) {
        import std.format : format;

        auto e = stmt(format(`component "%s"`, name));
        auto as = e.text("");

        e.text(" {");
        e.sep;
        auto s = e.base;
        s.suppressIndent(1);
        e.stmt("}", No.addSep).suppressThisIndent(1);

        return ComponentType(ComponentNameType(name), ComponentModuleType(s), ComponentAsType(as));
    }

    auto relate(T)(T a, T b, Relate relate) if (CanRelate!T) {
        import std.format : format;

        static if (is(T == ClassNameType)) {
            enum side_format = `"%s"`;
        } else static if (is(T == ComponentNameType)) {
            // BUG PlantUML 8036 and lower errors when a component relation uses apostrophe (")
            enum side_format = `%s`;
        }

        auto block = stmt("");
        auto left = block.text(format(side_format, cast(string) a));
        auto middle = block.text(format(" %s ", relateToString(relate)));
        auto right = block.text(format(side_format, cast(string) b));

        auto rl = Relation(RelateLeft(left), RelateRight(right),
                RelateMiddle(middle), RelateBlock(block));

        return rl;
    }

    auto unsafeRelate(string a, string b, string type) {
        import std.format : format;

        return RelationType(stmt(format(`%s %s %s`, a, type, b)));
    }

    // Suites
    Suite suite(string headline, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Suite(headline);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    Suite digraph(string name) {
        auto e = suite("digraph " ~ name);
        return e;
    }
}

private string paramsToString(T...)(auto ref T args) {
    import std.conv : to;

    string params;
    if (args.length >= 1) {
        params = to!string(args[0]);
    }
    if (args.length >= 2) {
        foreach (v; args[1 .. $]) {
            params ~= ", " ~ to!string(v);
        }
    }
    return params;
}

// Begin: Class Diagram functions
private alias CanHaveMethodSeq = AliasSeq!(ClassType, ClassModuleType);
private enum CanHaveMethod(T) = staticIndexOf!(T, CanHaveMethodSeq) >= 0;

private auto getM(T)(T m) {
    static if (is(T == ClassModuleType)) {
        return m;
    } else static if (is(T == ClassType)) {
        return m.m;
    } else {
        static assert(false, "Type not supported " ~ T.stringof);
    }
}

auto method(T)(T m, string txt) if (CanHaveMethod!T) {
    auto e = m.getM.stmt(txt);
    return e;
}

auto method(T)(T m, Flag!"isVirtual" isVirtual, string return_type, string name,
        Flag!"isConst" isConst) if (CanHaveMethod!T) {
    import std.format : format;

    auto e = m.getM.stmt(format("%s%s %s()%s", isVirtual ? "virtual " : "",
            return_type, name, isConst ? " const" : ""));
    return e;
}

auto method(T0, T...)(T m, Flag!"isVirtual" isVirtual, string return_type,
        string name, Flag!"isConst" isConst, auto ref T args) if (CanHaveMethod!T) {
    import std.format : format;

    string params = m.paramsToString(args);

    auto e = m.getM.stmt(format("%s%s %s(%s)%s", isVirtual ? "virtual " : "",
            return_type, name, params, isConst ? " const" : ""));
    return e;
}

auto ctor(T)(T m, string class_name) if (CanHaveMethod!T) {
    auto e = m.getM.stmt(class_name ~ "()");
    return e;
}

auto ctor_body(T0, T...)(T0 m, string class_name, auto ref T args)
        if (CanHaveMethod!T) {
    import std.format : format;

    string params = this.paramsToString(args);

    auto e = m.getM.class_suite(class_name, format("%s(%s)", class_name, params));
    return e;
}

/** Virtual d'tor.
 * Params:
 *  m = ?
 *  isVirtual = if evaluated to true prepend with virtual.
 *  class_name = name of the class to create a d'tor for.
 * Example:
 * ----
 * dtor(Yes.isVirtual, "Foo");
 * ----
 */
auto dtor(T)(T m, Flag!"isVirtual" isVirtual, string class_name)
        if (CanHaveMethod!T) {
    import std.format : format;

    auto e = m.getM.stmt(format("%s%s%s()", isVirtual ? "virtual " : "",
            class_name[0] == '~' ? "" : "~", class_name));
    return e;
}

auto dtor(T)(T m, string class_name) if (CanHaveMethod!T) {
    import std.format : format;

    auto e = m.getM.stmt(format("%s%s()", class_name[0] == '~' ? "" : "~", class_name));
    return e;
}

auto addSpot(T)(ref T m, string spot) if (is(T == ClassType)) {
    m.spot.clearChildren;

    auto spot_ = m.as.text(" " ~ spot);
    m.spot = spot_;

    return m.spot;
}
// End: Class Diagram functions

// Begin: Component Diagram functions
auto addAs(T)(ref T m) if (is(T == ComponentType) || is(T == ClassType)) {
    m.as.clearChildren;

    auto as = m.as.text(" as ");
    m.as = as;

    return as;
}
// End: Component Diagram functions

auto label(Relation m, string txt, LabelPos pos) {
    import std.format : format;

    // A "Left" -- "Right" B : "OnRelation"

    final switch (pos) with (LabelPos) {
    case Left:
        m.left.text(format(` "%s"`, txt));
        break;
    case Right:
        // it is not a mistake to put the right label on middle
        m.rel.text(format(`"%s" `, txt));
        break;
    case OnRelation:
        m.right.text(format(` : "%s"`, txt));
        break;
    }

    return m;
}

auto label(Relation m, string txt) {
    import std.format : format;

    m.right.text(format(` : "%s"`, txt));
    return m;
}

/** Affected by attribute end.
 * stmt ~ end
 *    <recursive>
 */
class Stmt : PlantumlModule {
    private string headline;

    this(string headline) {
        this.headline = headline;
    }

    override string renderIndent(int parent_level, int level) {
        string end = ("end" in attrs) ? attrs["end"] : "";
        string r = headline ~ end;

        if (!("noindent" in attrs)) {
            r = indent(r, parent_level, level);
        }

        return r;
    }
}

/** Affected by attribute begin, end, noindent.
 * headline ~ begin
 *     <recursive>
 * end
 * noindent affects post_recursive. If set no indention there.
 * r.length > 0 catches the case when begin or end is empty string. Used in switch/case.
 */
class Suite : PlantumlModule {
    private string headline;

    this(string headline) {
        this.headline = headline;
    }

    override string renderIndent(int parent_level, int level) {
        import std.ascii : newline;

        string begin = ("begin" in attrs) ? attrs["begin"] : " {" ~ newline;
        string r = headline ~ begin;

        if (r.length > 0 && !("noindent" in attrs)) {
            r = indent(r, parent_level, level);
        }
        return r;
    }

    override string renderPostRecursive(int parent_level, int level) {
        string r = "}";
        if ("end" in attrs) {
            r = attrs["end"];
        }

        if (r.length > 0 && !("noindent" in attrs)) {
            r = indent(r, parent_level, level);
        }
        return r;
    }
}

/** Generate a plantuml block ready to be rendered.
 */
struct PlantumlRootModule {
    private PlantumlModule root;

    static auto make() {
        typeof(this) r;
        r.root = new PlantumlModule;
        r.root.suppressIndent(1);

        return r;
    }

    PlantumlModule makeUml() {
        import std.ascii : newline;

        auto e = root.suite("")[$.begin = "@startuml" ~ newline, $.end = "@enduml"];
        return e;
    }

    PlantumlModule makeDot() {
        import std.ascii : newline;

        auto dot = root.suite("")[$.begin = "@startdot" ~ newline, $.end = "@enddot"];
        return dot;
    }

    auto render()
    in {
        assert(root !is null);
    }
    body {
        return root.render();
    }
}

@Name("should be a complete plantuml block ready to be rendered")
unittest {
    auto b = PlantumlRootModule.make();
    b.makeUml;

    b.render().shouldEqual("@startuml
@enduml
");
}

@Name("should be a block with a class")
unittest {
    auto r = PlantumlRootModule.make();
    auto c = r.makeUml;

    c.class_("A");

    r.render.shouldEqual(`@startuml
class "A"
@enduml
`);
}

// from now on assuming the block works correctly
@Name("should be two related classes")
unittest {
    auto c = new PlantumlModule;

    auto a = c.class_("A");
    auto b = c.class_("B");

    c.relate(a.name, b.name, Relate.WeakRelate);
    c.relate(a.name, b.name, Relate.Relate);
    c.relate(a.name, b.name, Relate.Compose);
    c.relate(a.name, b.name, Relate.Aggregate);
    c.relate(a.name, b.name, Relate.Extend);
    c.relate(a.name, b.name, Relate.ArrowTo);
    c.relate(a.name, b.name, Relate.AggregateArrowTo);

    c.render.shouldEqual(`    class "A"
    class "B"
    "A" .. "B"
    "A" -- "B"
    "A" o-- "B"
    "A" *-- "B"
    "A" --|> "B"
    "A" --> "B"
    "A" *--> "B"
`);
}

@Name("should be two related components")
unittest {
    auto c = new PlantumlModule;

    auto a = c.component("A");
    auto b = c.component("B");

    c.relate(a.name, b.name, Relate.WeakRelate);
    c.relate(a.name, b.name, Relate.Relate);
    c.relate(a.name, b.name, Relate.Compose);
    c.relate(a.name, b.name, Relate.Aggregate);
    c.relate(a.name, b.name, Relate.Extend);
    c.relate(a.name, b.name, Relate.ArrowTo);
    c.relate(a.name, b.name, Relate.AggregateArrowTo);

    c.render.shouldEqual(`    component "A"
    component "B"
    A .. B
    A -- B
    A o-- B
    A *-- B
    A --|> B
    A --> B
    A *--> B
`);
}

@Name("should be a labels on the relation between two components")
unittest {
    auto c = new PlantumlModule;

    auto a = c.component("A");
    auto b = c.component("B");

    auto l = c.relate(a.name, b.name, Relate.Relate);
    l.label("related");

    c.render.shouldEqual(`    component "A"
    component "B"
    A -- B : "related"
`);
}

@Name("should be a labels on the components over the relation line")
unittest {
    auto c = new PlantumlModule;

    auto a = c.component("A");
    auto b = c.component("B");

    auto l = c.relate(a.name, b.name, Relate.Relate);

    l.label("1", LabelPos.Left);
    l.label("2", LabelPos.Right);
    l.label("related", LabelPos.OnRelation);

    c.render.shouldEqual(`    component "A"
    component "B"
    A "1" -- "2" B : "related"
`);
}

@Name("Should be a class with a spot")
unittest {
    auto m = new PlantumlModule;

    {
        auto c = m.class_("A");
        c.addSpot.text("(D, orchid)");
    }

    {
        auto c = m.classBody("B");
        c.addSpot.text("(I, orchid)");
        c.method("fun()");
    }

    m.render.shouldEqual(`    class "A" << (D, orchid) >>
    class "B" << (I, orchid) >> {
        fun()
    }
`);
}

@Name("Should be a spot separated from the class name in a root module")
unittest {
    auto r = PlantumlRootModule.make;
    auto m = r.makeUml;

    {
        auto c = m.class_("A");
        c.addSpot.text("(D, orchid)");
    }

    {
        auto c = m.classBody("B");
        c.addSpot.text("(I, orchid)");
        c.method("fun()");
    }

    r.render.shouldEqual(`@startuml
class "A" << (D, orchid) >>
class "B" << (I, orchid) >> {
    fun()
}
@enduml
`);
}

@Name("Should be a component with an 'as'")
unittest {
    auto m = new PlantumlModule;
    auto c = m.component("A");

    c.addAs.text("a");

    m.render.shouldEqual(`    component "A" as a
`);
}
