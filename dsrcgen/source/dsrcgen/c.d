/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module dsrcgen.c;

import std.typecons : Flag, Yes, No;

import dsrcgen.base;

@safe:

///TODO: change to c-comment and make a separate for c++.
/** Affected by attribute begin
 * begin ~ comment
 */
class Comment : BaseModule {
    mixin Attrs;

    private string contents;

    /// Create a one liner comment.
    this(string contents) {
        this.contents = contents;
    }

    ///
    override string renderIndent(int parent_level, int level) {
        if ("begin" in attrs) {
            return indent(attrs["begin"] ~ contents, parent_level, level);
        }

        return indent("// " ~ contents, parent_level, level);
    }
}

/// Mixin of methods for creating semantic C content.
mixin template CModuleX(T) {
    mixin Attrs;

    /** Access to self.
     *
     * Useful in with-statements.
     */
    T _() {
        return this;
    }

    Comment comment(string comment) {
        auto e = new Comment(comment);
        append(e);
        e.sep;
        return e;
    }

    Text!T text(string content) {
        auto e = new Text!T(content);
        append(e);
        return e;
    }

    T base() {
        auto e = new T;
        append(e);
        return e;
    }

    // Statements
    Stmt!T stmt(string stmt_, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Stmt!T(stmt_);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    auto break_() {
        return stmt("break");
    }

    auto call(string name, string params) {
        import std.format : format;

        auto e = stmt(format("%s(%s)", name, params));
        return e;
    }

    auto call(T...)(string name, auto ref T args) {
        import std.format : format;

        string params = this.paramsToString(args);

        auto e = stmt(format("%s(%s)", name, params));
        return e;
    }

    auto continue_() {
        return stmt("continue");
    }

    auto return_() {
        return stmt("return");
    }

    auto return_(string expr) {
        return stmt("return " ~ expr);
    }

    auto goto_(string name) {
        import std.format : format;

        return stmt(format("goto %s", name));
    }

    auto label(string name) {
        import std.format : format;

        return stmt(format("%s:", name));
    }

    auto define(string name) {
        import std.format : format;

        auto e = stmt(format("#define %s", name));
        e[$.end = ""];
        return e;
    }

    auto define(string name, string value) {
        import std.format : format;

        // may need to replace \n with \\\n
        auto e = stmt(format("#define %s %s", name, value));
        e[$.end = ""];
        return e;
    }

    auto extern_(string value) {
        import std.format : format;

        return stmt(format("extern %s", value));
    }

    auto include(string filename) {
        import std.format : format;

        string f = filename;
        string incl;

        if (f.length > 1 && f[0] == '<') {
            incl = format("#include %s", f);
        } else {
            incl = format(`#include "%s"`, f);
        }

        auto e = stmt(incl)[$.end = ""];
        return e;
    }

    // Suites
    Suite!T suite(string headline, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Suite!T(headline);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    auto struct_(string name) {
        auto e = suite("struct " ~ name)[$.end = "};"];
        return e;
    }

    auto if_(string cond) {
        import std.format : format;

        return suite(format("if (%s)", cond));
    }

    auto else_if(string cond) {
        import std.format : format;

        return suite(format("else if (%s)", cond));
    }

    auto else_() {
        return suite("else");
    }

    auto enum_() {
        return suite("enum")[$.end = "};"];
    }

    auto enum_(string identifier) {
        return suite("enum " ~ identifier)[$.end = "};"];
    }

    auto enum_const(string name) {
        return stmt(name)[$.end = ","];
    }

    auto for_(string init, string cond, string next) {
        import std.format : format;

        return suite(format("for (%s; %s; %s)", init, cond, next));
    }

    auto while_(string cond) {
        import std.format : format;

        return suite(format("while (%s)", cond));
    }

    auto do_while(string cond) {
        import std.format : format;

        auto e = suite("do");
        e[$.end = format("} while (%s);", cond)];
        return e;
    }

    auto switch_(string cond) {
        import std.format : format;

        return suite(format("switch (%s)", cond));
    }

    auto case_(string val) {
        import std.format : format;

        auto e = suite(format("case %s:", val), No.addSep)[$.begin = "", $.end = ""];
        e.sep;
        return e;
    }

    auto default_() {
        auto e = suite("default:", No.addSep)[$.begin = "", $.end = ""];
        e.sep;
        return e;
    }

    auto func(string return_type, string name) {
        import std.format : format;

        auto e = stmt(format("%s %s()", return_type, name));
        return e;
    }

    auto func(T...)(string return_type, string name, auto ref T args) {
        import std.format : format;

        string params = paramsToString(args);

        auto e = stmt(format("%s %s(%s)", return_type, name, params));
        return e;
    }

    auto func_body(string return_type, string name) {
        import std.format : format;

        auto e = suite(format("%s %s()", return_type, name));
        return e;
    }

    auto func_body(T...)(string return_type, string name, auto ref T args) {
        import std.format : format;

        string params = paramsToString(args);

        auto e = suite(format("%s %s(%s)", return_type, name, params));
        return e;
    }

    auto IF(string name) {
        auto e = suite("#if " ~ name);
        e[$.begin = "", $.end = "#endif // " ~ name];
        e.sep;
        e.suppressIndent(1);
        return e;
    }

    auto IFDEF(string name) {
        import std.format : format;

        auto e = suite(format("#ifdef %s", name));
        e[$.begin = "", $.end = "#endif // " ~ name];
        e.sep;
        e.suppressIndent(1);
        return e;
    }

    auto IFNDEF(string name) {
        auto e = suite("#ifndef " ~ name);
        e[$.begin = "", $.end = "#endif // " ~ name];
        e.sep;
        e.suppressIndent(1);
        return e;
    }

    auto ELIF(string cond) {
        auto e = stmt("#elif " ~ cond);
        return e;
    }

    auto ELSE() {
        auto e = stmt("#else");
        return e;
    }
}

string paramsToString(T...)(auto ref T args) {
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

/// Represent a semantic item in C source.
class CModule : BaseModule {
    mixin CModuleX!(CModule);
}

private string stmt_append_end(string s, ref const string[string] attrs) pure nothrow {
    import std.string : inPattern;

    //TODO too much null checking, refactor.

    if (s is null) {
        string end = ";";
        if (auto v = "end" in attrs) {
            end = *v;
        }
        s ~= end;
    } else {
        bool in_pattern = false;
        try {
            in_pattern = inPattern(s[$ - 1], ";:,{");
        }
        catch (Exception e) {
        }

        if (!in_pattern && s[0] != '#') {
            string end = ";";
            if (auto v = "end" in attrs) {
                end = *v;
            }
            s ~= end;
        }
    }

    return s;
}

/** Affected by attribute end.
 * stmt ~ end
 *    <recursive>
 */
class Stmt(T) : T {
    private string headline;

    /// Content of the statement.
    this(string headline) {
        this.headline = headline;
    }

    override string renderIndent(int parent_level, int level) {
        string r = stmt_append_end(headline, attrs);

        if ("noindent" !in attrs) {
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
class Suite(T) : T {
    private string headline;

    /// Content of the suite/block.
    this(string headline) {
        this.headline = headline;
    }

    override string renderIndent(int parent_level, int level) {
        import std.ascii : newline;

        string r = headline ~ " {" ~ newline;
        if (auto v = "begin" in attrs) {
            r = headline ~ *v;
        }

        if (r.length > 0 && !("noindent" in attrs)) {
            r = indent(r, parent_level, level);
        }
        return r;
    }

    override string renderPostRecursive(int parent_level, int level) {
        string r = "}";
        if (auto v = "end" in attrs) {
            r = *v;
        }

        if (r.length > 0 && "noindent" !in attrs) {
            r = indent(r, parent_level, level);
        }
        return r;
    }
}

/// An expressioin in C.
struct E {
@safe pure:
    import std.conv : to;

    private string content;

    /// Content of the expression.
    this(string content) nothrow pure {
        this.content = content;
    }

    /// Convert argument via std.conv.to!string.
    this(T)(T content) nothrow pure {
        this.content = to!string(content);
    }

    /// Concatenate two expressions with ".".
    this(E lhs, string rhs) nothrow pure {
        this.content = lhs.content ~ "." ~ rhs;
    }

    /// ditto
    auto e(string lhs) nothrow pure const {
        return E(content ~ "." ~ lhs);
    }

    /// ditto
    auto e(E lhs) nothrow pure const {
        return E(content ~ "." ~ lhs.content);
    }

    /// Represent the semantic function call.
    auto opCall(T)(T value) pure const {
        return E(content ~ "(" ~ to!string(value) ~ ")");
    }

    // implicit
    @property string toString() pure const nothrow {
        return content;
    }

    alias toString this;

    /// String representation of the content. Explicit cast.
    T opCast(T : string)() pure const nothrow {
        return content;
    }

    /// Preprend the textual representation of the operator to the content.
    auto opUnary(string op)() pure nothrow const {
        static if (op == "+" || op == "-" || op == "*" || op == "++" || op == "--") {
            return E(mixin("\"" ~ op ~ "\"~content"));
        } else {
            static assert(0, "Operator " ~ op ~ " not implemented");
        }
    }

    /** Represent the semantic meaning of binary operators.
     *
     * ~ is special cased but OK for it doesn't exist in C/C++.
     */
    auto opBinary(string op, T)(in T rhs) pure nothrow const {
        static if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "&") {
            return E(mixin("content~\" " ~ op ~ " \"~to!string(rhs)"));
        } else static if (op == "~" && is(T == E)) {
            return E(content ~ " " ~ rhs.content);
        } else static if (op == "~") {
            return E(content = content ~ to!string(rhs));
        } else {
            static assert(0, "Operator " ~ op ~ " not implemented");
        }
    }

    /** Reconstruct the semantic "=" as affecting the content.
     *
     * Example:
     *   E("int x") = E(1) -> "x = 1"
     */
    auto opAssign(T)(T rhs) pure nothrow {
        this.content ~= " = " ~ to!string(rhs);
        return this;
    }
}

/** Code structure for generation of a C header.
 *
 * The content is structed as:
 *  doc
 *      header
 *          ifdef_guardbegin
 *              content
 *          ifdef_guard end
 *
 * Note that the indent is suppressed.
 */
struct CHModule {
    /// Document root.
    CModule doc;
    /// Usually a copyright header.
    CModule header;
    /// Main code content.
    CModule content;

    /**
     * Params:
     *   ifdef_guard = guard statement.
     */
    this(string ifdef_guard) {
        // Must suppress indentation to generate what is expected by the user.
        doc = new CModule;
        with (doc) {
            // doc is a container of the modules so should not affect indent.
            // header, content and footer is containers so should not affect indent.
            // ifndef guard usually never affect indent.
            suppressIndent(1);
            header = base;
            header.suppressIndent(1);
            with (IFNDEF(ifdef_guard)) {
                define(ifdef_guard);
                content = base;
                content.suppressIndent(1);
            }
        }
    }

    /// Render the content as a string.
    string render() {
        return doc.render();
    }
}

@("Test of statements")
unittest {
    string expect = "    77;
    break;
    continue;
    return 5;
    return long_value;
    goto foo;
    bar:
    #define foobar
    #define smurf 1
";

    auto x = new CModule();

    with (x) {
        stmt(E(77));
        break_;
        continue_;
        return_(E(5));
        return_("long_value");
        goto_("foo");
        label("bar");
        define("foobar");
        define("smurf", E(1));
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}

@("Test of preprocess statements")
unittest {
    string expect = "    #if foo
    inside;
    if {
        deep inside;
    }
    #endif // foo
    #ifdef bar
    inside;
    #endif // bar
    #ifndef foobar
    inside;
    #elif wee
    inside;
    #else
    inside;
    #endif // foobar
";

    auto x = new CModule();

    with (x) {
        with (IF("foo")) {
            stmt("inside");
            with (suite("if")) {
                stmt("deep inside");
            }
        }
        with (IFDEF("bar")) {
            stmt("inside");
        }
        with (IFNDEF("foobar")) {
            stmt("inside");
            ELIF("wee");
            stmt("inside");
            ELSE();
            stmt("inside");
        }
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}

@("Test of suites")
unittest {
    string expect = "
    foo {
    }
    if (foo) {
    }
    else if (bar) {
    }
    else {
    }
    for (x; y; z) {
    }
    while (x) {
    }
    do {
    } while (x);
    switch (x) {
    }
    case y:
        foo;
    default:
        foobar;
    int foobar(int x) {
    }
    int fun(int y);
";

    auto x = new CModule();
    with (x) {
        sep();
        suite("foo");
        if_("foo");
        else_if("bar");
        else_;
        for_("x", "y", "z");
        while_("x");
        do_while("x");
        switch_("x");
        with (case_("y")) {
            stmt("foo");
        }
        with (default_) {
            stmt("foobar");
        }
        func_body("int", "foobar", "int x");
        func("int", "fun", "int y");
    }

    auto rval = x.render;
    assert(rval == expect, rval);
}

@("Test of complicated switch")
unittest {
    string expect = "
    switch (x) {
        case 0:
            return 5;
            break;
        case 1:
            return 3;
            break;
        default:
            return -1;
    }
";

    auto x = new CModule();
    with (x) {
        sep();
        with (switch_("x")) {
            with (case_(E(0))) {
                return_(E(5));
                break_;
            }
            with (case_(E(1))) {
                return_(E(3));
                break_;
            }
            with (default_) {
                return_(E(-1));
            }
        }
    }

    auto rval = x.render;
    assert(rval == expect, rval);
}

@("Test of empty CSuite")
unittest {
    auto x = new Suite!CModule("test");
    assert(x.render == "test {\n}", x.render);
}

@("Test of stmt_append_end")
unittest {
    string[string] attrs;
    string stmt = "some_line";
    string result = stmt_append_end(stmt, attrs);
    assert(stmt ~ ";" == result, result);

    result = stmt_append_end(stmt ~ ";", attrs);
    assert(stmt ~ ";" == result, result);

    attrs["end"] = "{";
    result = stmt_append_end(stmt, attrs);
    assert(stmt ~ "{" == result, result);
}

@("Test of CSuite with formatting")
unittest {
    auto x = new Suite!CModule("if (x > 5)");
    assert(x.render() == "if (x > 5) {\n}", x.render);
}

@("Test of CSuite with simple text")
unittest {
    // also test that text(..) do NOT add a linebreak
    auto x = new Suite!CModule("foo");
    with (x) {
        text("bar");
    }
    assert(x.render() == "foo {\nbar}", x.render);
}

@("Test of CSuite with simple text and changed begin")
unittest {
    auto x = new Suite!CModule("foo");
    with (x[$.begin = "_:_"]) {
        text("bar");
    }
    assert(x.render() == "foo_:_bar}", x.render);
}

@("Test of CSuite with simple text and changed end")
unittest {
    auto x = new Suite!CModule("foo");
    with (x[$.end = "_:_"]) {
        text("bar");
    }
    assert(x.render() == "foo {\nbar_:_", x.render);
}

@("Test of nested CSuite")
unittest {
    auto x = new Suite!CModule("foo");
    with (x) {
        text("bar");
        sep();
        with (suite("smurf")) {
            comment("bar");
        }
    }
    assert(x.render() == "foo {
bar
    smurf {
        // bar
    }
}", x.render);
}

@("Test of text in CModule with guard")
unittest {
    auto hdr = CHModule("somefile_hpp");

    with (hdr.header) {
        text("header text");
        sep();
        comment("header comment");
    }
    with (hdr.content) {
        text("content text");
        sep();
        comment("content comment");
    }

    assert(hdr.render == "header text
// header comment
#ifndef somefile_hpp
#define somefile_hpp
content text
// content comment
#endif // somefile_hpp
", hdr.render);
}

@("Test of Expression. Type conversion")
unittest {
    import std.conv : to;

    string implicit = E("foo")(77);
    assert("foo(77)" == implicit, implicit);

    auto explicit = cast(string) E("foo")(77);
    assert("foo(77)" == explicit, explicit);

    auto to_string = to!string(E("foo")(77));
    assert("foo(77)" == to_string, to_string);
}

@("Test of Expression")
unittest {
    string expect = "foo
foo(77)
77 + 3
77 - 3
44 - 3 + 7
(44 - 3 + 7)
foo(42 + 43)
int x = 7
";
    auto x = new CModule();
    x.suppressIndent(1);

    x.text("foo");
    x.sep;
    x.text(E("foo")(77));
    x.sep;
    x.text(E(77) + 3);
    x.sep;
    x.text(E(77) - 3);
    x.sep;
    x.text(E(44) - E(3) + E(7));
    x.sep;
    x.text(E()(E(44) - E(3) + E(7)));
    x.sep;
    x.text(E("foo")(E(42) + 43));
    x.sep;
    x.text(E("int x") = 7);
    x.sep;

    auto rval = x.render;
    assert(rval == expect, rval);
}

@("Test of indent")
unittest {
    string expect = "    L2 1 {
        L3 1.1 {
        }
        L3 1.2 {
            L4 1.2.1 {
            }
        }
    }
";

    auto x = new CModule();

    with (x) {
        with (suite("L2 1")) {
            suite("L3 1.1");
            with (suite("L3 1.2")) {
                suite("L4 1.2.1");
            }
        }
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}

@("Test of single suppressing of indent")
unittest {
    string expect = "L1 1 {
L1 1.1 {
}
L1 1.2 {
    L2 1.2.1 {
    }
}
}
";

    auto x = new CModule();

    with (x) {
        suppressIndent(1);
        with (suite("L1 1")) {
            suite("L1 1.1");
            with (suite("L1 1.2")) {
                suite("L2 1.2.1");
            }
        }
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}

@("Test of nested suppressing of indent")
unittest {
    string expect = "L1 1 {
L1 1.1 {
}
L1 1.2 {
L1 1.2.1 {
    L2 1.2.1.1 {
    }
}
}
}
";

    auto x = new CModule();

    with (x) {
        suppressIndent(1);
        // suppressing L1 1 to be on the same level as x
        // affects L1 1 and the first level of children
        with (suite("L1 1")) {
            suite("L1 1.1"); // suppressed
            with (suite("L1 1.2")) {
                suppressIndent(1);
                with (suite("L1 1.2.1")) { // suppressed
                    suite("L2 1.2.1.1");
                }
            }
        }
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}

@("shall be an expression assignment")
unittest {
    auto expect = "    a = p;
";

    auto m = new CModule;
    auto e = E("a");
    e = E("p");
    m.stmt(e);

    assert(expect == m.render, m.render);
}

@("shall be a return with and without value")
unittest {
    auto expect = "    return;
    return a;
";

    auto m = new CModule;
    m.return_();
    m.return_("a");

    assert(expect == m.render, m.render);
}

@("shall be a C enum definition")
unittest {
    auto expect = "    enum {
    }
    enum A {
    };
    enum B {
        L0,
        L1 = 2,
    }
";

    auto m = new CModule;
    m.enum_;
    m.enum_("A");
    with (m.enum_("B")) {
        enum_const("L0");
        enum_const(E("L1") = E("2"));
    }
}

@("shall be a extern func")
unittest {
    auto expect = `    extern var;
`;
    auto m = new CModule;
    m.extern_("var");

    assert(expect == m.render, m.render);
}
