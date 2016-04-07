/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module dsrcgen.cpp;

import std.typecons : Flag, Yes, No;

import dsrcgen.base;

public import dsrcgen.c;

@safe:

mixin template CppModuleX() {
    // Statements
    auto friend(string expr) {
        return stmt("friend " ~ expr);
    }

    auto new_(string expr) {
        return stmt("new " ~ expr);
    }

    auto delete_(string expr) {
        return stmt("delete " ~ expr);
    }

    auto delete_array(string expr) {
        return stmt("delete [] " ~ expr);
    }

    // Suites
    /** Suites for C++ definitions for a class.
     * Useful for implementiong ctor, dtor and member methods for a class.
     * Params:
     *  class_name = name of the class.
     *  headline = whatever to append after class_name.
     * Example:
     * ----
     * class_suite("Simple", "Simple()");
     * ----
     * Generated code:
     * ----
     * Simple::Simple() {
     * }
     * ----
     */
    auto class_suite(string class_name, string headline) {
        import std.format : format;

        auto tmp = format("%s::%s", class_name, headline);
        auto e = suite(tmp, Yes.addSep);
        return e;
    }

    auto class_suite(string rval, string class_name, string headline) {
        import std.format : format;

        auto tmp = format("%s %s::%s", rval, class_name, headline);
        auto e = suite(tmp, Yes.addSep);
        return e;
    }

    auto ctor(T...)(string class_name, auto ref T args) {
        import std.format : format;

        string params = this.paramsToString(args);

        auto e = stmt(format("%s(%s)", class_name, params));
        return e;
    }

    auto ctor(string class_name) {
        auto e = stmt(class_name ~ "()");
        return e;
    }

    auto ctor_body(T...)(string class_name, auto ref T args) {
        import std.format : format;

        string params = this.paramsToString(args);

        auto e = class_suite(class_name, format("%s(%s)", class_name, params));
        return e;
    }

    auto ctor_body(string class_name) {
        import std.format : format;

        auto e = class_suite(class_name, format("%s()", class_name));
        return e;
    }

    /** Virtual d'tor.
     * Params:
     *  isVirtual = if evaluated to true prepend with virtual.
     *  class_name = name of the class to create a d'tor for.
     * Example:
     * ----
     * dtor(Yes.isVirtual, "Foo");
     * ----
     */
    auto dtor(Flag!"isVirtual" isVirtual, string class_name) {
        import std.format : format;

        auto e = stmt(format("%s%s%s()", isVirtual ? "virtual " : "",
                class_name[0] == '~' ? "" : "~", class_name));
        return e;
    }

    auto dtor(string class_name) {
        import std.format : format;

        auto e = stmt(format("%s%s()", class_name[0] == '~' ? "" : "~", class_name));
        return e;
    }

    /// Definition for a dtor.
    auto dtor_body(string class_name) {
        import std.format : format;

        string s = class_name;
        if (s[0] == '~') {
            s = s[1 .. $];
        }
        auto e = class_suite(class_name, format("~%s()", s));
        return e;
    }

    auto namespace(string n) {
        auto e = suite("namespace " ~ n)[$.end = "} //NS:" ~ n];
        return e;
    }

    auto class_(string n) {
        auto e = suite("class " ~ n)[$.end = "};"];
        return e;
    }

    auto class_(string name, string inherit) {
        import std.format : format;

        if (inherit.length == 0) {
            return class_(name);
        } else {
            auto e = suite(format("class %s : %s", name, inherit))[$.end = "};"];
            return e;
        }
    }

    auto public_() {
        auto e = suite("public:", No.addSep)[$.begin = "", $.end = ""];
        e.suppressThisIndent(1);
        e.sep;
        return e;
    }

    auto protected_() {
        auto e = suite("protected:", No.addSep)[$.begin = "", $.end = ""];
        e.suppressThisIndent(1);
        e.sep;
        return e;
    }

    auto private_() {
        auto e = suite("private:", No.addSep)[$.begin = "", $.end = ""];
        e.suppressThisIndent(1);
        e.sep;
        return e;
    }

    auto method(Flag!"isVirtual" isVirtual, string return_type, string name,
            Flag!"isConst" isConst) {
        import std.format : format;

        auto e = stmt(format("%s%s %s()%s", isVirtual ? "virtual " : "",
                return_type, name, isConst ? " const" : ""));
        return e;
    }

    auto method(T...)(Flag!"isVirtual" isVirtual, string return_type,
            string name, Flag!"isConst" isConst, auto ref T args) {
        import std.format : format;

        string params = this.paramsToString(args);

        auto e = stmt(format("%s%s %s(%s)%s", isVirtual ? "virtual " : "",
                return_type, name, params, isConst ? " const" : ""));
        return e;
    }

    auto method_body(string return_type, string class_name, string name, Flag!"isConst" isConst) {
        import std.format : format;

        auto e = class_suite(return_type, class_name, format("%s()%s", name,
                isConst ? " const" : ""));
        return e;
    }

    auto method_body(T...)(string return_type, string class_name, string name,
            Flag!"isConst" isConst, auto ref T args) {
        import std.format : format;

        string params = this.paramsToString(args);

        auto e = class_suite(return_type, class_name, format("%s(%s)%s", name,
                params, isConst ? " const" : ""));
        return e;
    }

    auto method_inline(Flag!"isVirtual" isVirtual, string return_type,
            string name, Flag!"isConst" isConst) {
        import std.format : format;

        auto e = suite(format("%s%s %s()%s", isVirtual ? "virtual " : "",
                return_type, name, isConst ? " const" : ""));
        return e;
    }

    auto method_inline(T...)(Flag!"isVirtual" isVirtual, string return_type,
            string name, Flag!"isConst" isConst, auto ref T args) {
        import std.format : format;

        string params = this.paramsToString(args);

        auto e = suite(format("%s%s %s(%s)%s", isVirtual ? "virtual " : "",
                return_type, name, params, isConst ? " const" : ""));
        return e;
    }
}

class CppModule : BaseModule {
    mixin CModuleX;
    mixin CppModuleX;
}

/// Code generation for C++ header.
struct CppHModule {
    CppModule doc;
    CppModule header;
    CppModule content;
    CppModule footer;

    this(string ifdef_guard) {
        // Must suppress indentation to generate what is expected by the user.
        doc = new CppModule;
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
            footer = base;
            footer.suppressIndent(1);
        }
    }

    auto render() {
        return doc.render();
    }
}

/** Template expressions in C++.
 *
 * Convenient when using templates.
 *
 * a = Et("static_cast")("char*");
 * b = a("foo"); // static_cast<char*>(foo);
 * c = a("bar"); // static_cast<char*>(bar);
 *
 * v = Et("vector")("int");
 * v0 = v ~ E("foo"); // vector<int> foo;
 * v1 = v("bar"); // vector<int>(bar);
 */
pure struct Et {
    import dsrcgen.c : E;
    import std.conv : to;
    import std.string : format;
    import std.traits : isSomeString;

    private string tmpl;

    struct Ett {
        private string tmpl;
        private string params;

        this(string tmpl, string params) pure nothrow {
            this.tmpl = tmpl;
            this.params = params;
        }

        auto opCall(T)(T value) pure const nothrow {
            return E(this.toString)(value);
        }

        // implicit
        @property string toString() pure const nothrow {
            return tmpl ~ "<" ~ params ~ ">";
        }

        alias toString this;

        // explicit
        T opCast(T : string)() pure const nothrow {
            return tmpl ~ "<" ~ params ~ ">";
        }

        auto opBinary(string op, T)(in T rhs) pure const nothrow {
            static if (op == "~" && is(T == E)) {
                return E(toString() ~ " " ~ rhs.toString);
            } else static if (op == "~") {
                return E(toString() ~ " " ~ to!string(rhs));
            } else {
                static assert(0, "Operator " ~ op ~ " not implemented");
            }
        }
    }

    this(T)(T tmpl) pure nothrow if (isSomeString!T) {
        this.tmpl = tmpl;
    }

    this(T)(T tmpl) pure nothrow if (!isSomeString!T) {
        this.tmpl = to!string(tmpl);
    }

    auto opCall(T)(T params) pure const nothrow {
        return Ett(tmpl, to!string(params));
    }
}

//@name("Test of C++ suits")
unittest {
    string expect = "
    namespace foo {
    } //NS:foo
    class Foo {
    public:
        Foo();
        Foo(int y);
        ~Foo();
        virtual ~Foo();
    };
    class Foo : Bar {
    };
public:
    return 5;
protected:
    return 7;
private:
    return 8;
";
    auto x = new CppModule();
    with (x) {
        sep;
        namespace("foo");
        with (class_("Foo")) {
            public_;
            auto ctor0 = ctor("Foo");
            auto ctor1 = ctor("Foo", "int y");
            auto dtor0 = dtor("Foo");
            auto dtor1 = dtor(Yes.isVirtual, "Foo");
        }
        class_("Foo", "Bar");
        with (public_) {
            return_(E(5));
        }
        with (protected_) {
            return_(E(7));
        }
        with (private_) {
            return_(E(8));
        }
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}

//@name("Test new and delete")
unittest {
    auto expect = "    new foo;
    delete bar;
    delete [] wart;
";

    auto x = new CppModule;
    with (x) {
        new_("foo");
        delete_("bar");
        delete_array("wart");
    }

    auto r = x.render;
    assert(expect == r, r);
}

// Test Et composition.
unittest {
    auto m = new CppModule;
    m.suppressIndent(1);

    auto expect = "static_cast<char*>(foo);
static_cast<char*>(bar);
";
    auto a = Et("static_cast")("char*");
    m.stmt(a("foo"));
    m.stmt(a("bar"));
    assert(expect == m.render, m.render);

    m = new CppModule;
    m.suppressIndent(1);
    expect = "vector<int> foo;
vector<int>(bar);
";
    auto v = Et("vector")("int");
    m.stmt(v ~ E("foo"));
    m.stmt(v("bar"));
    assert(expect == m.render, m.render);
}

// should generate an inlined class method
unittest {
    auto expect = "    void foo() {
    }
    void bar(int foo) {
    }
";

    auto m = new CppModule;
    m.method_inline(No.isVirtual, "void", "foo", No.isConst);
    m.method_inline(No.isVirtual, "void", "bar", No.isConst, "int foo");

    assert(expect == m.render, m.render);
}
