/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.analyze.containers;

import std.array : appender;

import std.typecons;

import translator.Type : TypeKind, makeTypeKind, duplicate;

import logger = std.experimental.logger;

public:

/// Name of a C++ namespace.
alias CppNs = Typedef!(string, string.init, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];
/// Nesting of C++ namespaces as a string.
alias CppNsNesting = Typedef!(string, string.init, "CppNsNesting");

alias CppVariable = Typedef!(string, string.init, "CppVariable");
alias TypeKindVariable = Tuple!(TypeKind, "type", CppVariable, "name");
alias CppParam = Typedef!(TypeKindVariable, TypeKindVariable.init, "CppParam");
alias CppReturnType = Typedef!(TypeKind, TypeKind.init, "CppReturnType");

// Types for classes
alias CppClassName = Typedef!(string, string.init, "CppClassName");
alias CppClassNesting = Typedef!(string, string.init, "CppNesting");
alias CppVirtualClass = Typedef!(VirtualType, VirtualType.No, "CppVirtualClass");

// Types for methods
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppConstMethod = Typedef!(bool, bool.init, "CppConstMethod");
alias CppVirtualMethod = Typedef!(VirtualType, VirtualType.No, "CppVirtualMethod");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");
alias CParam = Typedef!(TypeKindVariable, TypeKindVariable.init, "CppParam");
alias CReturnType = Typedef!(TypeKind, TypeKind.init, "CppReturnType");

enum VirtualType {
    No,
    Yes,
    Pure
}

pure @safe nothrow struct CFunction {
    @disable this();

    this(const CFunctionName name, const CParam[] params_, const CReturnType return_type) {
        this.name = name;
        this.returnType_ = duplicate(cast(const TypedefType!CReturnType) return_type);

        //TODO how do you replace this with a range?
        CParam[] tmp;
        foreach (p; params_) {
            tmp ~= CParam(TypeKindVariable(duplicate(p.type), p.name));
        }
        this.params = tmp;
    }

    /// Function with no parameters.
    this(const CFunctionName name, const CReturnType return_type) {
        this(name, CParam[].init, return_type);
    }

    /// Function with no parameters and returning void.
    this(const CFunctionName name) {
        CReturnType void_ = makeTypeKind("void", "void", false, false, false);
        this(name, CParam[].init, void_);
    }

    auto paramRange() @nogc @safe pure nothrow {
        import std.array;

        return params[];
    }

    invariant() {
        assert(name.length > 0);
        assert(returnType_.name.length > 0);
        assert(returnType_.toString.length > 0);

        foreach (p; params) {
            assert(p.name.length > 0);
            assert(p.type.name.length > 0);
            assert(p.type.toString.length > 0);
        }
    }

    @property auto returnType() const {
        return this.returnType_;
    }

    immutable CFunctionName name;

private:
    CParam[] params;
    CReturnType returnType_;
}

pure @safe nothrow struct CppMethod {
    @disable this();

    this(const CppMethodName name, const CppParam[] params_,
        const CppReturnType return_type, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name = name;
        this.returnType = duplicate(cast(const TypedefType!CppReturnType) return_type);
        this.isConst = cast(TypedefType!CppConstMethod) const_;
        this.isVirtual = cast(TypedefType!CppVirtualMethod) virtual;

        //TODO how do you replace this with a range?
        CppParam[] tmp;
        foreach (p; params_) {
            tmp ~= CppParam(TypeKindVariable(duplicate(p.type), p.name));
        }
        this.params = tmp;
    }

    /// Function with no parameters.
    this(CppMethodName name, CppReturnType return_type, CppConstMethod const_,
        CppVirtualMethod virtual) {
        this(name, CppParam[].init, return_type, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(CppMethodName name, CppConstMethod const_ = false, CppVirtualMethod virtual = VirtualType.No) {
        CppReturnType void_ = makeTypeKind("void", "void", false, false, false);
        this(name, CppParam[].init, void_, const_, virtual);
    }

    auto paramRange() @nogc @safe pure nothrow {
        import std.array;

        return params[];
    }

    string toString() @safe pure {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : takeOne;

        auto ps = appender!string();
        auto pr = paramRange();
        pr.takeOne.each!(a => formattedWrite(ps, "%s %s", a.type.toString, a.name.str));
        pr.each!(a => formattedWrite(ps, ", %s %s", a.type.toString, a.name.str));

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s)", returnType.toString, name.str, ps.data);

        return rval.data;
    }

    invariant() {
        assert(name.length > 0);
        assert(returnType.name.length > 0);
        assert(returnType.toString.length > 0);

        foreach (p; params) {
            assert(p.name.length > 0);
            assert(p.type.name.length > 0);
            assert(p.type.toString.length > 0);
        }
    }

private:
    immutable bool isConst;
    immutable VirtualType isVirtual;
    CppMethodName name;
    CppParam[] params;
    CppReturnType returnType;
}

pure @safe nothrow struct CppClass {
    @disable this();

    this(const CppClassName name, const CppVirtualClass virtual = VirtualType.No) {
        this.name = name;
        this.isVirtual = cast(TypedefType!CppVirtualClass) virtual;
    }

    void put(CppMethod method) {
        methods ~= method;
    }

    auto methodRange() @safe pure {
        import std.array;

        return methods[];
    }

    string toString() @safe pure {
        import std.array : appender;
        import std.conv : to;
        import std.algorithm : each;
        import std.ascii : newline;
        import std.format : formattedWrite;

        auto r = appender!string();

        formattedWrite(r, "class %s (isVirtual %s) {%s", name.str, to!string(isVirtual),
            newline);
        methodRange.each!(a => formattedWrite(r, "  %s%s", a.toString, newline));
        formattedWrite(r, "}%s", newline);

        return r.data;
    }

    invariant() {
        assert(name.length > 0);
    }

    immutable VirtualType isVirtual;

private:
    CppClassName name;
    CppMethod[] methods;
}

pure @safe nothrow struct CppNamespace {
    @disable this();

    static auto makeAnonymous() {
        return CppNamespace(CppNsStack.init);
    }

    /// A namespace without any nesting.
    static auto makeSimple(string name) {
        return CppNamespace([CppNs(name)]);
    }

    this(const CppNsStack stack) {
        if (stack.length > 0) {
            this.name = stack[$ - 1];
        }
        this.isAnonymous = stack.length == 0;
        this.stack = stack.dup;
    }

    void put(CFunction f) {
        funcs ~= f;
    }

    void put(CppClass s) {
        classes ~= s;
    }

    /** The implementation of the stack is such that new elements are appended
     * to the end. Therefor the range normal direction is from the end of the
     * array to the beginning.
     */
    auto nsNestingRange() @nogc @safe pure nothrow {
        static @nogc struct Result {
            CppNsStack stack;
            @property auto front() @safe pure nothrow {
                assert(!empty, "Can't get front of an empty range");
                return stack[$ - 1];
            }

            @property auto back() @safe pure nothrow {
                assert(!empty, "Can't get back of an empty range");
                return stack[0];
            }

            @property void popFront() @safe pure nothrow {
                assert(!empty, "Can't pop front of an empty range");
                stack = stack[0 .. $ - 1];
            }

            @property void popBack() @safe pure nothrow {
                assert(!empty, "Can't pop back of an empty range");
                stack = stack[1 .. $];
            }

            @property bool empty() @safe pure nothrow const {
                return stack.length == 0;
            }

            @property auto save() @safe pure nothrow {
                return Result(stack);
            }
        }

        return Result(stack);
    }

    auto classRange() @nogc @safe pure nothrow {
        import std.array;

        return classes[];
    }

    auto funcRange() @nogc @safe pure nothrow {
        import std.array;

        return funcs[];
    }

    string toString() @safe pure {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : takeOne, retro, dropOne;
        import std.ascii : newline;

        auto ns_app = appender!string();
        auto ns_r = nsNestingRange().retro;
        ns_r.takeOne.each!(a => ns_app.put(a.str));
        ns_r.popFront;
        ns_r.each!(a => formattedWrite(ns_app, "::%s", a.str));

        auto app = appender!string();
        formattedWrite(app, "namespace %s {%s", ns_app.data, newline);

        formattedWrite(app, "}%s", newline);

        return app.data;
    }

    immutable bool isAnonymous;
    immutable CppNs name;

private:
    CppNsStack stack;
    CppClass[] classes;
    CFunction[] funcs;
}

pure @safe nothrow struct Root {
    void put(CFunction f) {
        funcs ~= f;
    }

    void put(CppClass s) {
        classes ~= s;
    }

    void put(CppNamespace ns) {
        this.ns ~= ns;
    }

    string toString() {
        import std.algorithm : each;
        import std.array : appender;
        import std.format : formattedWrite;

        auto app = appender!string();

        namespaceRange.each!(a => app.put(a.toString));

        return app.data;
    }

    auto namespaceRange() @nogc @safe pure nothrow {
        import std.array;

        return ns[];
    }

    auto classRange() @nogc @safe pure nothrow {
        import std.array;

        return classes[];
    }

    auto funcRange() @nogc @safe pure nothrow {
        import std.array;

        return funcs[];
    }

private:
    CppNamespace[] ns;
    CppClass[] classes;
    CFunction[] funcs;
}

string str(T)(T value) @property @safe pure nothrow if (is(T : T!TL, TL : string)) {
    return cast(string) value;
}

//@name("Test of creating a function")
unittest {
    auto f = CFunction(CFunctionName("nothing"));
    assert(f.name == "nothing");
    assert(f.returnType.name == "void");
}

//@name("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(CppMethodName("voider"));
    assert(m.isConst == false);
    assert(m.isVirtual == VirtualType.No);
    assert(m.name == "voider");
    assert(m.params.length == 0);
    assert(m.returnType.name == "void");
}

//@name("Test of creating a class")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"));
    c.put(m);
    assert(c.methods.length == 1);
    assert(c.toString == "class Foo (isVirtual No) {\n  void voider()\n}\n", c.toString);
}

//@name("Create an anonymous namespace struct")
unittest {
    import std.conv;

    auto n = CppNamespace(CppNsStack.init);
    assert(n.name.length == 0, text(n.name.length));
    assert(n.isAnonymous == true, text(n.isAnonymous));
}

//@name("Create a namespace struct two deep")
unittest {
    auto stack = [CppNs("foo"), CppNs("bar")];
    auto n = CppNamespace(stack);
    assert(n.name == "bar", cast(string) n.name);
    assert(n.isAnonymous == false);
}

//@name("Test of iterating over parameters in a class")
unittest {
    import std.array : appender;

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"));
    c.put(m);

    auto app = appender!string();
    foreach (d; c.methodRange) {
        app.put(d.toString);
    }

    assert(app.data == "void voider()", app.data);
}

//@name("Test of printing root")
unittest {
    Root root;

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"));
    c.put(m);
    root.put(c);

    root.put(CppNamespace.makeSimple("simple"));

    assert(root.toString == "", root.toString);
}
