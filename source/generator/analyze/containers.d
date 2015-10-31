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

import std.typecons;

import translator.Type : TypeKind, makeTypeKind, duplicate;
import generator.analyze.wip : arrayRange;

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
alias CppAccess = Typedef!(AccessType, AccessType.Private, "CppAccess");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");
alias CParam = Typedef!(TypeKindVariable, TypeKindVariable.init, "CParam");
alias CReturnType = Typedef!(TypeKind, TypeKind.init, "CReturnType");

enum VirtualType {
    No,
    Yes,
    Pure
}

enum AccessType {
    Public,
    Protected,
    Private
}

/// Information about free functions.
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

    auto paramRange() const @nogc @safe pure nothrow {
        return arrayRange(params);
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

    @property auto returnType() const pure @safe {
        return this.returnType_;
    }

    string toString() const @safe pure {
        import std.array : appender;
        import std.algorithm : each;
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.range : takeOne;

        auto ps = appender!string();
        auto pr = paramRange();
        pr.takeOne.each!(a => formattedWrite(ps, "%s %s", a.type.toString, a.name.str));
        if (!pr.empty) {
            pr.popFront;
            pr.each!(a => formattedWrite(ps, ", %s %s", a.type.toString, a.name.str));
        }

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s);%s", returnType.toString, name.str, ps.data,
            newline);

        return rval.data;
    }

    immutable CFunctionName name; /// Function name.

private:
    CParam[] params;
    CReturnType returnType_;
}

/// Constructor or destructor methods.
pure @safe nothrow struct CppTorMethod {
    @disable this();

    this(const CppMethodName name, const CppParam[] params_, const CppAccess access,
        const CppVirtualMethod virtual) {
        this.name = name;
        this.accessType = access;
        this.isVirtual = cast(TypedefType!CppVirtualMethod) virtual;

        //TODO how do you replace this with a range?
        CppParam[] tmp;
        foreach (p; params_) {
            tmp ~= CppParam(TypeKindVariable(duplicate(p.type), p.name));
        }
        this.params = tmp;
    }

    auto paramRange() const @nogc @safe pure nothrow {
        return arrayRange(params);
    }

    string toString() const @safe pure {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : takeOne;

        auto ps = appender!string();
        auto pr = paramRange();
        pr.takeOne.each!(a => formattedWrite(ps, "%s %s", a.type.toString, a.name.str));
        if (!pr.empty) {
            pr.popFront;
            pr.each!(a => formattedWrite(ps, ", %s %s", a.type.toString, a.name.str));
        }

        auto rval = appender!string();
        switch (isVirtual) {
        case VirtualType.Yes:
        case VirtualType.Pure:
            rval.put("virtual ");
            break;
        default:
        }
        formattedWrite(rval, "%s(%s)", name.str, ps.data);

        return rval.data;
    }

    void opAssign(CppTorMethod rhs) {
        this = rhs;
    }

    invariant() {
        assert(name.length > 0);

        foreach (p; params) {
            assert(p.name.length > 0);
            assert(p.type.name.length > 0);
            assert(p.type.toString.length > 0);
        }
    }

    immutable VirtualType isVirtual;
    immutable CppAccess accessType;

private:
    CppMethodName name;
    CppParam[] params;
}

pure @safe nothrow struct CppMethod {
    @disable this();

    this(const CppMethodName name, const CppParam[] params_,
        const CppReturnType return_type, const CppAccess access,
        const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name = name;
        this.returnType = duplicate(cast(const TypedefType!CppReturnType) return_type);
        this.accessType = access;
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
    this(const CppMethodName name, const CppReturnType return_type,
        const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this(name, CppParam[].init, return_type, access, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(const CppMethodName name, const CppAccess access,
        const CppConstMethod const_ = false, const CppVirtualMethod virtual = VirtualType.No) {
        CppReturnType void_ = makeTypeKind("void", "void", false, false, false);
        this(name, CppParam[].init, void_, access, const_, virtual);
    }

    void put(CppParam p) {
        params ~= p;
    }

    auto paramRange() const @nogc @safe pure nothrow {
        return arrayRange(params);
    }

    string toString() const @safe pure {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : takeOne;

        auto ps = appender!string();
        auto pr = paramRange();
        pr.takeOne.each!(a => formattedWrite(ps, "%s %s", a.type.toString, a.name.str));
        if (!pr.empty) {
            pr.popFront;
            pr.each!(a => formattedWrite(ps, ", %s %s", a.type.toString, a.name.str));
        }

        auto rval = appender!string();
        switch (isVirtual) {
        case VirtualType.Yes:
        case VirtualType.Pure:
            rval.put("virtual ");
            break;
        default:
        }
        formattedWrite(rval, "%s %s(%s)", returnType.toString, name.str, ps.data);

        if (isConst) {
            rval.put(" const");
        }
        switch (isVirtual) {
        case VirtualType.Pure:
            rval.put(" = 0");
            break;
        default:
        }

        return rval.data;
    }

    void opAssign(CppMethod rhs) {
        this = rhs;
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

    immutable bool isConst;
    immutable VirtualType isVirtual;
    immutable CppAccess accessType;

private:
    CppMethodName name;
    CppParam[] params;
    CppReturnType returnType;
}

// TODO consider make CppClass be able to hold nested classes.
pure @safe nothrow struct CppClass {
    import std.variant;

    @disable this();

    this(const CppClassName name, const CppVirtualClass virtual = VirtualType.No) {
        this.name = name;
        this.isVirtual = cast(TypedefType!CppVirtualClass) virtual;
    }

    void put(T)(T func) @trusted nothrow if (is(T == CppMethod) || is(T == CppTorMethod)) {
        final switch (cast(TypedefType!CppAccess) func.accessType) {
        case AccessType.Public:
            methods_pub ~= CppFunc(func);
            break;
        case AccessType.Protected:
            methods_prot ~= CppFunc(func);
            break;
        case AccessType.Private:
            methods_priv ~= CppFunc(func);
            break;
        }
    }

    auto methodRange() @nogc @safe pure nothrow {
        import std.range;

        return chain(methods_pub, methods_prot, methods_priv);
    }

    auto methodPublicRange() @nogc @safe pure nothrow {
        return arrayRange(methods_pub);
    }

    auto methodProtectedRange() @nogc @safe pure nothrow {
        return arrayRange(methods_prot);
    }

    auto methodPrivateRange() @nogc @safe pure nothrow {
        return arrayRange(methods_priv);
    }

    ///TODO make the function const.
    string toString() @safe {
        import std.array : Appender, appender;
        import std.conv : to;
        import std.algorithm : each;
        import std.ascii : newline;
        import std.format : formattedWrite;

        static string funcToString(ref CppFunc func) @trusted {
            //dfmt off
            return func.visit!((CppMethod a) => a.toString,
                               (CppTorMethod a) => a.toString);
            //dfmt on
        }

        auto r = appender!string();

        formattedWrite(r, "class %s { // isVirtual %s%s", name.str,
            to!string(isVirtual), newline);
        if (methods_pub.length > 0) {
            formattedWrite(r, "public:%s", newline);
            methods_pub.each!(a => formattedWrite(r, "  %s;%s", funcToString(a), newline));
        }
        if (methods_prot.length > 0) {
            formattedWrite(r, "protected:%s", newline);
            methods_prot.each!(a => formattedWrite(r, "  %s;%s", funcToString(a), newline));
        }
        if (methods_priv.length > 0) {
            formattedWrite(r, "private:%s", newline);
            methods_priv.each!(a => formattedWrite(r, "  %s;%s", funcToString(a), newline));
        }
        formattedWrite(r, "}; //Class:%s%s", name.str, newline);

        return r.data;
    }

    invariant() {
        assert(name.length > 0);
    }

    immutable VirtualType isVirtual;

private:
    CppClassName name;

    alias CppFunc = Algebraic!(CppMethod, CppTorMethod);
    CppFunc[] methods_pub;
    CppFunc[] methods_prot;
    CppFunc[] methods_priv;
}

pure @safe nothrow struct CppNamespace {
    @disable this();

    static auto makeAnonymous() {
        return CppNamespace(CppNsStack.init);
    }

    /// A namespace without any nesting.
    static auto make(CppNs name) {
        return CppNamespace([name]);
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

    void put(CppNamespace ns) {
        namespaces ~= ns;
    }

    /** Traverse stack from top to bottom.
     * The implementation of the stack is such that new elements are appended
     * to the end. Therefor the range normal direction is from the end of the
     * array to the beginning.
     */
    auto nsNestingRange() @nogc @safe pure nothrow {
        import std.range : retro;

        return arrayRange(stack).retro;
    }

    auto classRange() @nogc @safe pure nothrow {
        return arrayRange(classes);
    }

    auto funcRange() @nogc @safe pure nothrow {
        return arrayRange(funcs);
    }

    auto namespaceRange() @nogc @safe pure nothrow {
        return arrayRange(namespaces);
    }

    string toString() @safe {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : retro;
        import std.ascii : newline;

        auto ns_app = appender!string();
        auto ns_r = nsNestingRange().retro;
        string ns_top_name;
        if (!ns_r.empty) {
            ns_top_name = ns_r.back.str;
            ns_app.put(ns_r.front.str);
            ns_r.popFront;
            ns_r.each!(a => formattedWrite(ns_app, "::%s", a.str));
        }

        auto app = appender!string();
        formattedWrite(app, "namespace %s { //%s%s", ns_top_name, ns_app.data, newline);
        funcRange.each!(a => formattedWrite(app, "%s", a.toString));
        classRange.each!(a => formattedWrite(app, "%s", a.toString));
        namespaceRange.each!(a => formattedWrite(app, "%s", a.toString));
        formattedWrite(app, "} //NS:%s%s", ns_top_name, newline);

        return app.data;
    }

    immutable bool isAnonymous;
    immutable CppNs name;

private:
    CppNsStack stack;
    CppClass[] classes;
    CFunction[] funcs;
    CppNamespace[] namespaces;
}

pure @safe nothrow struct CppRoot {
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
        import std.ascii : newline;
        import std.format : formattedWrite;

        auto app = appender!string();

        funcRange.each!(a => app.put(a.toString));
        app.put(newline);
        classRange.each!(a => app.put(a.toString));
        app.put(newline);
        namespaceRange.each!(a => app.put(a.toString));

        return app.data;
    }

    auto namespaceRange() @nogc @safe pure nothrow {
        return arrayRange(ns);
    }

    auto classRange() @nogc @safe pure nothrow {
        return arrayRange(classes);
    }

    auto funcRange() @nogc @safe pure nothrow {
        return arrayRange(funcs);
    }

private:
    CppNamespace[] ns;
    CppClass[] classes;
    CFunction[] funcs;
}

string str(T)(const T value) @safe pure nothrow {
    return cast(string) value;
}

//@name("Test of creating a function")
unittest {
    auto f = CFunction(CFunctionName("nothing"));
    assert(f.returnType.name == "void");
}

//@name("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    assert(m.isConst == false);
    assert(m.isVirtual == VirtualType.No);
    assert(m.name == "voider");
    assert(m.params.length == 0);
    assert(m.returnType.name == "void");
    assert(m.accessType == AccessType.Public);
}

//@name("Test of creating a class")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    assert(c.methods_pub.length == 1);
    assert(
        c.toString == "class Foo { // isVirtual No\npublic:\n  void voider();\n}; //Class:Foo\n",
        c.toString);
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
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);

    auto app = appender!string();
    foreach (d; c.methodRange) {
        app.put(d.toString);
    }

    assert(app.data == "void voider()", app.data);
}

//@name("Test of toString for a free function")
unittest {
    auto ptk = makeTypeKind("char", "char*", false, false, true);
    auto rtk = makeTypeKind("int", "int", false, false, false);
    auto f = CFunction(CFunctionName("nothing"), [CParam(TypeKindVariable(ptk,
        CppVariable("x"))), CParam(TypeKindVariable(ptk, CppVariable("y")))], CReturnType(rtk));

    assert(f.toString == "int nothing(char* x, char* y);\n", f.toString);
}

//@name("Test of toString for CppTorMethod")
unittest {
    auto tk = makeTypeKind("char", "char*", false, false, true);
    auto p = [CppParam(TypeKindVariable(tk, CppVariable("x")))];

    auto ctor = CppTorMethod(CppMethodName("ctor"), p,
        CppAccess(AccessType.Public), CppVirtualMethod(VirtualType.No));
    auto dtor = CppTorMethod(CppMethodName("~dtor"), CppParam[].init,
        CppAccess(AccessType.Public), CppVirtualMethod(VirtualType.Yes));

    assert(ctor.toString == "ctor(char* x)", ctor.toString);
    assert(dtor.toString == "virtual ~dtor()", dtor.toString);
}

//@name("Test of toString for CppClass")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public)));

    {
        auto m = CppTorMethod(CppMethodName("Foo"), CppParam[].init,
            CppAccess(AccessType.Public), CppVirtualMethod(VirtualType.No));
        c.put(m);
    }

    {
        auto tk = makeTypeKind("int", "int", false, false, false);
        auto m = CppMethod(CppMethodName("fun"), CppReturnType(tk),
            CppAccess(AccessType.Protected), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("gun"),
            CppReturnType(makeTypeKind("char", "char*", false, false, true)),
            CppAccess(AccessType.Private), CppConstMethod(false),
            CppVirtualMethod(VirtualType.No));
        m.put(CppParam(TypeKindVariable(makeTypeKind("int", "int", false,
            false, false), CppVariable("x"))));
        m.put(CppParam(TypeKindVariable(makeTypeKind("int", "int", false,
            false, false), CppVariable("y"))));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("wun"),
            CppReturnType(makeTypeKind("int", "int", false, false, true)),
            CppAccess(AccessType.Public), CppConstMethod(true), CppVirtualMethod(VirtualType.No));
        c.put(m);
    }

    assert(c.toString == "class Foo { // isVirtual No
public:
  void voider();
  Foo();
  int wun() const;
protected:
  virtual int fun() = 0;
private:
  char* gun(int x, int y);
}; //Class:Foo
",
        c.toString);
}

//@name("Test of toString for CppNamespace")
unittest {
    auto ns = CppNamespace.make(CppNs("simple"));

    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public)));
    ns.put(c);

    assert(ns.toString == "namespace simple { //simple
class Foo { // isVirtual No
public:
  void voider();
}; //Class:Foo
} //NS:simple
",
        ns.toString);
}

//@name("Should show nesting of namespaces as valid C++ code")
unittest {
    auto stack = [CppNs("foo"), CppNs("bar")];
    auto n = CppNamespace(stack);
    assert("namespace bar { //foo::bar
} //NS:bar
" == n.toString, n.toString);
}

//@name("Test of toString for CppRoot")
unittest {
    CppRoot root;

    { // free function
        auto f = CFunction(CFunctionName("nothing"));
        root.put(f);
    }

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    root.put(c);

    root.put(CppNamespace.make(CppNs("simple")));

    assert(root.toString == "void nothing();

class Foo { // isVirtual No
public:
  void voider();
}; //Class:Foo

namespace simple { //simple
} //NS:simple
",
        root.toString);
}

//@name("CppNamespace.toString should return nested namespace")
unittest {
    auto stack = [CppNs("Depth1"), CppNs("Depth2"), CppNs("Depth3")];
    auto depth1 = CppNamespace(stack[0 .. 1]);
    auto depth2 = CppNamespace(stack[0 .. 2]);
    auto depth3 = CppNamespace(stack[0 .. $]);

    depth2.put(depth3);
    depth1.put(depth2);

    assert(depth1.toString == "namespace Depth1 { //Depth1
namespace Depth2 { //Depth1::Depth2
namespace Depth3 { //Depth1::Depth2::Depth3
} //NS:Depth3
} //NS:Depth2
} //NS:Depth1
",
        depth1.toString);
}
