/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module dsrcgen.cpp;

import dsrcgen.base;

public import dsrcgen.c;

@safe:

mixin template CppModuleX() {
    // Statements
    auto friend(string expr) {
        return stmt("friend " ~ expr);
    }

    auto static_cast(string type, string expr) {
        return stmt("static_cast<" ~ type ~ ">(" ~ expr ~ ")");
    }

    auto dynamic_cast(string type, string expr) {
        return stmt("dynamic_cast<" ~ type ~ ">(" ~ expr ~ ")");
    }

    auto reinterpret_cast(string type, string expr) {
        return stmt("reinterpret_cast<" ~ type ~ ">(" ~ expr ~ ")");
    }

    auto const_cast(string type, string expr) {
        return stmt("const_cast<" ~ type ~ ">(" ~ expr ~ ")");
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
        auto tmp = format("%s::%s", class_name, headline);
        auto e = new Suite!(typeof(this))(tmp);
        append(e);
        return e;
    }

    auto class_suite(string rval, string class_name, string headline) {
        auto tmp = format("%s %s::%s", rval, class_name, headline);
        auto e = new Suite!(typeof(this))(tmp);
        append(e);
        return e;
    }

    auto ctor(T...)(string class_name, auto ref T args) {
        string params = this.paramsToString(args);

        auto e = stmt(format("%s(%s)", class_name, params));
        return e;
    }

    auto ctor(string class_name) {
        auto e = stmt(class_name ~ "()");
        return e;
    }

    auto ctor_body(T...)(string class_name, auto ref T args) {
        string params = this.paramsToString(args);

        auto e = class_suite(class_name, format("%s(%s)", class_name, params));
        return e;
    }

    auto ctor_body(string class_name) {
        auto e = class_suite(class_name, format("%s()", class_name));
        return e;
    }

    /** Virtual d'tor.
     * Params:
     *  virtual_ = if evaluated to true prepend with virtual.
     *  class_name = name of the class to create a d'tor for.
     * Example:
     * ----
     * dtor(true, "Foo");
     * ----
     * TODO better solution for virtual. A boolean is kind of adhoc.
     */
    auto dtor(bool virtual_, string class_name) {
        auto e = stmt(format("%s%s%s()", virtual_ ? "virtual " : "",
            class_name[0] == '~' ? "" : "~", class_name));
        return e;
    }

    auto dtor(string class_name) {
        auto e = stmt(format("%s%s()", class_name[0] == '~' ? "" : "~", class_name));
        return e;
    }

    /// Definition for a dtor.
    auto dtor_body(string class_name) {
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
        if (inherit.length == 0) {
            return class_(name);
        } else {
            auto e = suite(format("class %s : %s", name, inherit))[$.end = "};"];
            return e;
        }
    }

    auto public_() {
        auto e = suite("public:", false)[$.begin = "", $.end = ""];
        e.suppressThisIndent(1);
        e.sep;
        return e;
    }

    auto protected_() {
        auto e = suite("protected:", false)[$.begin = "", $.end = ""];
        e.suppressThisIndent(1);
        e.sep;
        return e;
    }

    auto private_() {
        auto e = suite("private:", false)[$.begin = "", $.end = ""];
        e.suppressThisIndent(1);
        e.sep;
        return e;
    }

    auto method(bool virtual_, string return_type, string name, bool const_) {
        auto e = stmt(format("%s%s %s()%s", virtual_ ? "virtual " : "",
            return_type, name, const_ ? " const" : ""));
        return e;
    }

    auto method(T...)(bool virtual_, string return_type, string name, bool const_,
        auto ref T args) {
        string params = this.paramsToString(args);

        auto e = stmt(format("%s%s %s(%s)%s", virtual_ ? "virtual " : "",
            return_type, name, params, const_ ? " const" : ""));
        return e;
    }

    auto method_body(string return_type, string class_name, string name, bool const_) {
        auto e = suite(format("%s %s::%s()%s", return_type, class_name, name,
            const_ ? " const" : ""));
        return e;
    }

    auto method_body(T...)(string return_type, string class_name, string name,
        bool const_, auto ref T args) {
        string params = this.paramsToString(args);

        auto e = suite(format("%s %s::%s(%s)%s", return_type, class_name, name,
            params, const_ ? " const" : ""));
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

//@name("Test of cast statements")
unittest {
    auto expect = "    static_cast<char>(foo);
    dynamic_cast<char*>(bar);
    reinterpret_cast<int>(wart);
    const_cast<const int>(driver);
";

    auto x = new CppModule;
    with (x) {
        static_cast("char", "foo");
        dynamic_cast("char*", "bar");
        reinterpret_cast("int", "wart");
        const_cast("const int", "driver");
    }

    auto r = x.render;
    assert(expect == r, r);
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
