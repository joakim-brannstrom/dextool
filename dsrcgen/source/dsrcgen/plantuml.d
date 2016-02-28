// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsrcgen.plantuml;

import dsrcgen.base;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    struct Name {
        string n;
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
    AggregateArrowTo
}

private string relateToString(Relate relate) {
    string r_type;
    final switch (relate) with (Relate) {
    case WeakRelate:
        r_type = "..";
        break;
    case Relate:
        r_type = "--";
        break;
    case Compose:
        r_type = "O--";
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
    }

    return r_type;
}

enum LabelPos {
    Left,
    Right,
    OnRelation
}

class PlantumlModule : BaseModule {
    import std.meta : AliasSeq;
    import std.meta : staticIndexOf;
    import std.traits : ReturnType;
    import std.typecons : Typedef, Tuple;

    alias ClassModuleType = Typedef!(typeof(this), typeof(this).init, "ClassModuleType");
    alias ClassType = Tuple!(string, "name", ClassModuleType, "m");

    alias ComponentModuleType = Typedef!(typeof(this), typeof(this).init, "ComponentModuleType");
    alias ComponentType = Tuple!(string, "name", ComponentModuleType, "m");

    alias RelationType = Typedef!(ReturnType!stmt, ReturnType!stmt.init, "RelationType");

    mixin template RelateTypes(Tleft, Tright, Trel, Tblock) {
        alias RelateLeft = Typedef!(Tleft, Tleft.init, "RelateLeft");
        alias RelateRight = Typedef!(Tright, Tright.init, "RelateRight");
        alias RelateMiddle = Typedef!(Trel, Trel.init, "RelateMiddle");
        alias RelateBlock = Typedef!(Tblock, Tblock.init, "RelationBlock");
        alias Relation = Tuple!(RelateLeft, "left", RelateRight, "right",
                RelateMiddle, "rel", RelateBlock);
    }

    mixin RelateTypes!(Text!(typeof(this)), Stmt, Stmt, typeof(this));

    // Types that can be related between each other
    alias CanRelateSeq = AliasSeq!(ClassType, ComponentType);
    enum CanRelate(T) = staticIndexOf!(T, CanRelateSeq) >= 0;

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
    auto stmt(string stmt_, bool separator = true) {
        auto e = new Stmt(stmt_);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    auto class_(string name) {
        return ClassType(name, ClassModuleType(stmt("class " ~ name)));
    }

    auto component(string name) {
        return ComponentType(name, ComponentModuleType(stmt("component " ~ name)));
    }

    auto relate(T)(T a, T b, Relate relate) if (CanRelate!T) {
        auto block = stmt("");
        block.suppressIndent(1);

        auto left = block.text(a.name);
        auto middle = block.stmt(relateToString(relate), false);
        middle.setIndentation(1);
        auto right = block.stmt(b.name, false);
        right.setIndentation(1);

        auto rl = Relation(RelateLeft(left), RelateRight(right),
                RelateMiddle(middle), RelateBlock(block));

        return rl;
    }

    auto unsafeRelate(string a, string b, string type) {
        import std.format : format;

        return RelationType(stmt(format("%s %s %s", a, type, b)));
    }

    // Suites
    auto suite(string headline, bool separator = true) {
        auto e = new Suite(headline);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }
}

auto label(PlantumlModule.Relation m, string txt, LabelPos pos) {
    import std.format : format;

    // A "Left" -- "Right" B : "OnRelation"

    final switch (pos) with (LabelPos) {
    case Left:
        m.left.text(format(` "%s"`, txt));
        break;
    case Right:
        // it is not a mistake to put the right label on middle
        m.rel.text(format(` "%s"`, txt));
        break;
    case OnRelation:
        m.right.text(format(` : "%s"`, txt));
        break;
    }

    return m;
}

auto label(PlantumlModule.Relation m, string txt) {
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
        string end = "";
        string r = headline;

        if ("end" in attrs) {
            end = attrs["end"];
        }

        if (!("noindent" in attrs)) {
            r = indent(r, parent_level, level);
        }

        return r ~ end;
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

        string r = headline ~ " {" ~ newline;
        if ("begin" in attrs) {
            r = headline ~ attrs["begin"];
        }

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
    PlantumlModule content;

    static auto make() {
        import std.ascii : newline;

        auto r = new typeof(this);
        r.root = new PlantumlModule;
        r.root.suppressIndent(1);
        r.content = r.root.suite("")[$.begin = "@startuml" ~ newline, $.end = "@enduml"];

        return r;
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

    b.render().shouldEqual("@startuml
@enduml
");
}

@Name("should be a block with a class")
unittest {
    auto r = PlantumlRootModule.make();
    auto c = r.content;

    c.class_("A");

    r.render.shouldEqual("@startuml
class A
@enduml
");
}

// from now on assuming the block works correctly
@Name("should be two related classes")
unittest {
    auto c = new PlantumlModule;

    auto a = c.class_("A");
    auto b = c.class_("B");

    c.relate(a, b, Relate.WeakRelate);
    c.relate(a, b, Relate.Relate);
    c.relate(a, b, Relate.Compose);
    c.relate(a, b, Relate.Aggregate);
    c.relate(a, b, Relate.Extend);
    c.relate(a, b, Relate.ArrowTo);
    c.relate(a, b, Relate.AggregateArrowTo);

    c.render.shouldEqual("    class A
    class B
    A .. B
    A -- B
    A O-- B
    A *-- B
    A --|> B
    A --> B
    A *--> B
");
}

@Name("should be two related components")
unittest {
    auto c = new PlantumlModule;

    auto a = c.component("A");
    auto b = c.component("B");

    c.relate(a, b, Relate.WeakRelate);
    c.relate(a, b, Relate.Relate);
    c.relate(a, b, Relate.Compose);
    c.relate(a, b, Relate.Aggregate);
    c.relate(a, b, Relate.Extend);
    c.relate(a, b, Relate.ArrowTo);
    c.relate(a, b, Relate.AggregateArrowTo);

    c.render.shouldEqual("    component A
    component B
    A .. B
    A -- B
    A O-- B
    A *-- B
    A --|> B
    A --> B
    A *--> B
");
}

@Name("should be a labels on the relation between two components")
unittest {
    auto c = new PlantumlModule;

    auto a = c.component("A");
    auto b = c.component("B");

    auto l = c.relate(a, b, Relate.Relate);
    l.label("related");

    c.render.shouldEqual(`    component A
    component B
    A -- B : "related"
`);
}

@Name("should be a labels on the components over the relation line")
unittest {
    auto c = new PlantumlModule;

    auto a = c.component("A");
    auto b = c.component("B");

    auto l = c.relate(a, b, Relate.Relate);

    l.label("1", LabelPos.Left);
    l.label("2", LabelPos.Right);
    l.label("related", LabelPos.OnRelation);

    c.render.shouldEqual(`    component A
    component B
    A "1" -- "2" B : "related"
`);
}
