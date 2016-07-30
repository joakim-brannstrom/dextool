// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsrcgen.plantuml;

import std.meta : AliasSeq, staticIndexOf;
import std.traits : ReturnType;
import std.typecons : Flag, Yes, No, Typedef, Tuple;

import dsrcgen.base;

version (Have_unit_threaded) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string n;
    }

    /// Fallback when unit_threaded doon't exist.
    private void shouldEqual(T0, T1)(T0 value, T1 expect) {
        assert(value == expect, value);
    }
}

@safe:

/** A plantuml comment using ''' as is.
 *
 * Compared to Text a comment is affected by indentation.
 */
class Comment : BaseModule {
    mixin Attrs;

    private string contents;

    /// Construct a one-liner comment from contents.
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

/// Converter for enum Relate to plantuml syntax.
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

alias NoteType = Typedef!(PlantumlModule, null, "NoteType");

alias RelationType = Typedef!(ReturnType!(PlantumlModule.stmt),
        ReturnType!(PlantumlModule.stmt).init, "RelationType");

/** A relation in plantuml has three main positions that can be modified.
 *
 * Block
 *  left middle right
 */
private mixin template RelateTypes(Tleft, Tright, Trel, Tblock) {
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

/** Semantic representation in D of PlantUML elements.
 *
 * All created instances are stored internally.
 * The returned instances is thus to allow the user to further manipulate or
 * add nesting content.
 */
class PlantumlModule : BaseModule {
    mixin Attrs;

    /** Make a Comment followed by a separator.
     *
     * Affected by indentation.
     *
     * TODO should have an addSep like stmt have.
     */
    auto comment(string comment) {
        auto e = new Comment(comment);
        e.sep;
        append(e);
        return e;
    }

    /** Make a raw Text.
     *
     * Note it is intentional that the text object do NOT have a separator. It
     * is to allow detailed "surgical" insertion of raw text/data when no
     * semantical "helpers" exist for a specific use case.
     */
    auto text(string content) {
        auto e = new Text!(typeof(this))(content);
        append(e);
        return e;
    }

    /** A basic building block with no content.
     *
     * Useful when a "node" is needed to add further content in.
     * The node is affected by indentation.
     */
    auto base() {
        auto e = new typeof(this);
        append(e);
        return e;
    }

    /** Make a statement with an optional separator.
     *
     * A statement is commonly an individual item or at the most a line.
     *
     * Params:
     *   stmt_ = raw text to use as the statement
     *   separator = flag determining if a separator is added
     *
     * Returns: Stmt instance stored in this.
     */
    Stmt stmt(string stmt_, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Stmt(stmt_);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    /** Make a UML class without any content.
     *
     * Return: A tuple allowing further modification.
     */
    ClassType class_(string name) {
        import std.format : format;

        auto e = stmt(format(`class "%s"`, name));
        auto as = e.text("");
        auto spot = as.text("");

        return ClassType(ClassNameType(name), ClassModuleType(e),
                ClassSpotType(spot), ClassAsType(as));
    }

    /** Make a UML component without any content.
     *
     * Return: A tuple allowing further modification.
     */
    auto component(string name) {
        import std.format : format;

        auto e = stmt(format(`component "%s"`, name));
        auto as = e.text("");

        return ComponentType(ComponentNameType(name), ComponentModuleType(e), ComponentAsType(as));
    }

    /** Make a relation between two things in plantuml.
     *
     * Ensured that the relation is well formed at compile time.
     * Allows further manipulation of the relation and still ensuring
     * correctness at compile time.
     *
     * Params:
     *  a = left relation
     *  b = right relation
     *  relate = type of relation between a/b
     */
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

    /** Raw relate of a "type" b.
     */
    auto unsafeRelate(string a, string b, string type) {
        import std.format : format;

        return RelationType(stmt(format(`%s %s %s`, a, type, b)));
    }

    /** Make a floating note.
     *
     * It will need to be related to an object.
     */
    auto note(string name) {
        ///TODO only supporting free floating for now
        auto block = stmt("");
        auto body_ = block.text(`note "`);
        block.text(`" as ` ~ name);

        return NoteType(body_);
    }

    // Suites

    /** Make a suite/block as a child of "this" with an optional separator.
     *
     * The separator is inserted after the block.
     *
     * Returns: Suite instance stored in this.
     */
    Suite suite(string headline, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Suite(headline);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    /** Make a UML namespace with an optional separator.
     * The separator is inserted after the block.
     */
    auto namespace(string name, Flag!"addSep" separator = Yes.addSep) {
        auto e = suite("namespace " ~ name);
        if (separator) {
            sep();
        }
        return e;
    }

    /** Make a PlantUML block for an inline Graphviz graph with an optional
     * separator.
     * The separator is inserted after the block.
     */
    Suite digraph(string name, Flag!"addSep" separator = Yes.addSep) {
        auto e = suite("digraph " ~ name);
        if (separator) {
            sep();
        }
        return e;
    }

    /** Make a UML class with content (methods, members).
     *
     * Return: A tuple allowing further modification.
     */
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

    /** Make a UML component with content.
     *
     * Return: A tuple allowing further modification.
     */
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

/** Make a method in a UML class diagram.
 *
 * Only possible for those that it makes sense such as class diagrams.
 *
 * Params:
 *  m = ?
 *  txt = raw text representing the method.
 *
 * Example:
 * ---
 * auto m = new PlantumlModule;
 * class_ = m.classBody("A");
 * class_.method("void fun();");
 * ---
 */
auto method(T)(T m, string txt) if (CanHaveMethod!T) {
    auto e = m.getM.stmt(txt);
    return e;
}

///
unittest {
    auto m = new PlantumlModule;
    auto class_ = m.classBody("A");
    class_.method("void fun();");
}

/** Make a method that takes no parameters in a UML class diagram.
 *
 * A helper function to get the representation of virtual, const etc correct.
 *
 * Params:
 *  m = ?
 *  return_type = ?
 *  name = name of the class to create a d'tor for
 *  isConst = ?
 */
auto method(T)(T m, Flag!"isVirtual" isVirtual, string return_type, string name,
        Flag!"isConst" isConst) if (CanHaveMethod!T) {
    import std.format : format;

    auto e = m.getM.stmt(format("%s%s %s()%s", isVirtual ? "virtual " : "",
            return_type, name, isConst ? " const" : ""));
    return e;
}

/** Make a method that takes arbitrary parameters in a UML class diagram.
 *
 * The parameters are iteratively converted to strings.
 *
 * Params:
 *  m = ?
 *  return_type = ?
 *  name = name of the class to create a d'tor for
 *  isConst = ?
 */
auto method(T0, T...)(T m, Flag!"isVirtual" isVirtual, string return_type,
        string name, Flag!"isConst" isConst, auto ref T args) if (CanHaveMethod!T) {
    import std.format : format;

    string params = m.paramsToString(args);

    auto e = m.getM.stmt(format("%s%s %s(%s)%s", isVirtual ? "virtual " : "",
            return_type, name, params, isConst ? " const" : ""));
    return e;
}

/** Make a constructor without any parameters in a UML class diagram.
 *
 * Params:
 *  m = ?
 *  class_name = name of the class to create a d'tor for.
 */
auto ctor(T)(T m, string class_name) if (CanHaveMethod!T) {
    auto e = m.getM.stmt(class_name ~ "()");
    return e;
}

/** Make a constructor that takes arbitrary number of parameters.
 *
 * Only applicable for UML class diagram.
 *
 * The parameters are iteratively converted to strings.
 *
 * Params:
 *  m = ?
 *  class_name = name of the class to create a d'tor for.
 */
auto ctorBody(T0, T...)(T0 m, string class_name, auto ref T args)
        if (CanHaveMethod!T) {
    import std.format : format;

    string params = this.paramsToString(args);

    auto e = m.getM.class_suite(class_name, format("%s(%s)", class_name, params));
    return e;
}

/** Make a destructor in a UML class diagram.
 * Params:
 *  m = ?
 *  isVirtual = if evaluated to true prepend with virtual.
 *  class_name = name of the class to create a d'tor for.
 */
auto dtor(T)(T m, Flag!"isVirtual" isVirtual, string class_name)
        if (CanHaveMethod!T) {
    import std.format : format;

    auto e = m.getM.stmt(format("%s%s%s()", isVirtual ? "virtual " : "",
            class_name[0] == '~' ? "" : "~", class_name));
    return e;
}

///
unittest {
    auto m = new PlantumlModule;
    auto class_ = m.classBody("Foo");
    class_.dtor(Yes.isVirtual, "Foo");
}

/** Make a destructor in a UML class diagram.
 * Params:
 *  m = ?
 *  class_name = name of the class to create a d'tor for.
 */
auto dtor(T)(T m, string class_name) if (CanHaveMethod!T) {
    import std.format : format;

    auto e = m.getM.stmt(format("%s%s()", class_name[0] == '~' ? "" : "~", class_name));
    return e;
}

/** Add a "spot" to a class in a class diagram.
 *
 * TODO i think there is a bug here. There is an order dependency of who is
 * called first, addSpot or addAs.  Both extend "as" which means that if
 * addSpot is called before addAs it will be "interesting".
 *
 * The documentation for PlantUML describes what it is.
 * Example of a spot:
 * class A << I, #123456 >>
 *         '--the spot----'
 *
 * Example:
 * ---
 * auto m = new PlantumlModule;
 * auto class_ = m.class_("A");
 * class_.addSpot("<< I, #123456 >>");
 * ---
 */
auto addSpot(T)(ref T m, string spot) if (is(T == ClassType)) {
    m.spot.clearChildren;
    m.spot = m.as.text(" " ~ spot);

    return m.spot;
}

/// Creating a plantuml spot.
/// Output:
/// class A << I, #123456 >>
///         '--the spot----'
unittest {
    auto m = new PlantumlModule;
    auto class_ = m.class_("A");
    class_.addSpot("<< I, #123456 >>");

    m.render.shouldEqual(`    class "A" << I, #123456 >>
`);
}

// End: Class Diagram functions

// Begin: Component Diagram functions

/** Add a PlantUML renaming of a class or component.
 */
auto addAs(T)(ref T m) if (is(T == ComponentType) || is(T == ClassType)) {
    m.as.clearChildren;

    auto as = m.as.text(" as ");
    m.as = as;

    return as;
}
// End: Component Diagram functions

/** Add a label to an existing relation.
 *
 * The meaning of LabelPos.
 * A "Left" -- "Right" B : "OnRelation"
 */
auto label(Relation m, string txt, LabelPos pos) {
    import std.format : format;

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

///
unittest {
    auto m = new PlantumlModule;
    auto c0 = m.class_("A");
    auto c1 = m.class_("B");
    auto r0 = m.relate(c0.name, c1.name, Relate.Compose);
    r0.label("foo", LabelPos.Right);
}

/** Add a raw label "on" the relationship line.
 */
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

    ///
    this(string headline) {
        this.headline = headline;
    }

    /// See_Also: BaseModule
    override string renderIndent(int parent_level, int level) {
        auto end = "end" in attrs;
        string r = headline ~ (end is null ? "" : *end);

        if ("noindent" !in attrs) {
            r = indent(r, parent_level, level);
        }

        return r;
    }
}

/** A plantuml block.
 *
 * Affected by attribute begin, end, noindent.
 * headline ~ begin
 *     <recursive>
 * end
 * noindent affects post_recursive. If set no indention there.
 * r.length > 0 catches the case when begin or end is empty string. Used in switch/case.
 */
class Suite : PlantumlModule {
    private string headline;

    ///
    this(string headline) {
        this.headline = headline;
    }

    override string renderIndent(int parent_level, int level) {
        import std.ascii : newline;

        string r;
        if (auto begin = "begin" in attrs) {
            r = headline ~ *begin;
        } else {
            r = headline ~ " {" ~ newline;
        }

        if (r.length > 0 && "noindent" !in attrs) {
            r = indent(r, parent_level, level);
        }
        return r;
    }

    override string renderPostRecursive(int parent_level, int level) {
        string r = "}";
        if (auto end = "end" in attrs) {
            r = *end;
        }

        if (r.length > 0 && "noindent" !in attrs) {
            r = indent(r, parent_level, level);
        }
        return r;
    }
}

/** Generate a plantuml block ready to be rendered.
 */
struct PlantumlRootModule {
    private PlantumlModule root;

    /// Make a root module with suppressed indent of the first level.
    static auto make() {
        typeof(this) r;
        r.root = new PlantumlModule;
        r.root.suppressIndent(1);

        return r;
    }

    /// Make a module contained in the root suitable for plantuml diagrams.
    PlantumlModule makeUml() {
        import std.ascii : newline;

        auto e = root.suite("")[$.begin = "@startuml" ~ newline, $.end = "@enduml"];
        return e;
    }

    /// Make a module contained in the root suitable for grahviz dot diagrams.
    PlantumlModule makeDot() {
        import std.ascii : newline;

        auto dot = root.suite("")[$.begin = "@startdot" ~ newline, $.end = "@enddot"];
        return dot;
    }

    /// Textually render the module tree.
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
        c.addSpot("<< (D, orchid) >>");
    }

    {
        auto c = m.classBody("B");
        c.addSpot("<< (I, orchid) >>");
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
        c.addSpot("<< (D, orchid) >>");
    }

    {
        auto c = m.classBody("B");
        c.addSpot("<< (I, orchid) >>");
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

@Name("Should be a namespace")
unittest {
    auto m = new PlantumlModule;
    auto ns = m.namespace("ns");

    m.render.shouldEqual(`    namespace ns {
    }
`);
}
