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
module generator.stub.containers;

import std.algorithm : each;
import std.ascii : newline;
import std.conv : to;
import std.string : format;
import std.typecons : Tuple;

import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule, E;

import generator.stub.convert : toString;
import generator.stub.mangling : NameMangling, mangleToStubDataClass,
    mangleToStubClassName, mangleToStubDataClassInternalVariable,
    mangleToStubStructType, mangleToStubStructMember;
import generator.stub.types;

import tested;

version (unittest) {
    shared static this() {
        import std.exception;

        enforce(runUnitTests!(generator.stub.containers)(new ConsoleTestResultWriter),
            "Unit tests failed.");
    }
}

/** Variables discovered during traversal of AST that data storage in the stub.
 * A common case is pointers to callbacks and parameters.
 *
 * NameMangling affects how the types and variables are translated to C++ code.
 * See translate() for details.
 *
 * Chose to not use the built-in associative array because it doesn't preserve
 * the order.
 *
 * Example:
 * ---
 * VariableContainer foo;
 * foo.push(NameMangling.Plain, "int", "ctor_x");
 * ---
 * The generated declaration is then:
 * ---
 * int ctor_x;
 * ---
 */
struct VariableContainer {
    @disable this();

    this(StubPrefix stub_prefix, CallbackNs cb_ns, CallbackPrefix cb_prefix,
        StubNs data_ns, CppClassName class_name) {
        import std.string : toLower;

        this.stub_prefix = stub_prefix;
        this.stub_prefix_lower = StubPrefix((cast(string) stub_prefix).toLower);
        this.cb_ns = cb_ns;
        this.cb_prefix = cb_prefix;
        this.data_ns = data_ns;
        this.class_name = class_name;
    }

    void push(const NameMangling mangling, const TypeName tn, const CppMethodName grouping) pure @safe nothrow {
        import std.algorithm : canFind;

        if (!groups.canFind(grouping))
            groups ~= grouping;
        vars ~= InternalType(mangling, tn, grouping);
    }

    void push(const NameMangling mangling, const CppType type,
        const CppVariable name, const CppMethodName grouping) pure @safe nothrow {
        push(mangling, TypeName(type, name), grouping);
    }

    void push(const NameMangling mangling, const ref TypeName[] tn, const CppMethodName grouping) pure @safe nothrow {
        tn.each!(a => push(mangling, a, grouping));
    }

    /// Number of variables stored.
    @property auto length() {
        return vars.length;
    }

    void render(T0, T1)(const CppNsNesting nesting, ref T0 hdr, ref T1 impl) const {
        auto hdr_structs = hdr.base;
        auto impl_structs = impl.base;
        hdr_structs.suppressIndent(1);
        impl_structs.suppressIndent(1);

        auto impl_data = impl.base;
        impl_data.suppressIndent(1);

        // create data class containing the stub interface
        auto data_class = mangleToStubDataClass(stub_prefix);
        auto hdr_data = hdr.class_(data_class.str);
        auto hdr_data_pub = hdr_data.public_;
        hdr_data.sep;
        auto hdr_data_priv = hdr_data.private_;

        with (hdr_data_pub) {
            ctor(data_class.str);
            dtor(data_class.str);
            sep(2);
        }

        CppModule ctor_init;
        with (impl_data) {
            ctor_init = ctor_body(data_class.str);
            sep(2);
            dtor_body(data_class.str);
            sep(2);
        }

        // fill with data
        foreach (g; groups) {
            renderGroup(g, nesting, hdr_structs, impl_structs, ctor_init);
            renderDataFunc(g, hdr_data_pub, hdr_data_priv, impl_data);
        }
    }

    private void renderGroup(T0, T1)(CppMethodName group, CppNsNesting nesting,
        ref T0 hdr, ref T1 impl, ref T1 ctor_init_impl) const {
        string stub_data_name = stub_prefix ~ group;

        auto group_class = hdr.class_(stub_data_name);
        auto group_pub = group_class.public_;
        auto group_priv = group_class.private_;
        with (group_priv) {
            string ns = nesting.str.length == 0 ? "" : "::" ~ nesting.str;
            string stub_class = mangleToStubClassName(stub_prefix, class_name).str;
            friend(E("class " ~ ns ~ "::" ~ stub_class));
            sep(2);
        }

        foreach (item; vars) {
            if (item.group == group) {
                CppMethodName get_method = "Get" ~ item.typename.name.str;
                CppMethodName set_method = "Set" ~ item.typename.name.str;

                renderGetSetHdr(item, get_method, set_method, group_pub, group_priv);
                renderGetSetImpl(item, data_ns, CppClassName(stub_data_name),
                    get_method, set_method, impl);
            }
        }
        renderInit(TypeName(CppType(stub_data_name), CppVariable("value")),
            group, hdr, impl, ctor_init_impl);
        hdr.sep;
    }

    /** Render the interface used to access test functionality for a group.
     * A group is a function.
     *
     * Generated functions depend on the type mangling.
     * They can be all or some of:
     *  GetCallback
     *  SetCallback
     *  GetCallCounter
     *  Reset
     *  SetReturn
     * Variables are:
     *  pointer to a namespace::Isomefunc*
     */
    private void renderGetSetHdr(T0, T1)(InternalType it,
        const CppMethodName get_method, const CppMethodName set_method, ref T0 hdr_pub,
        T1 hdr_priv) const {
        TypeName tn = InternalToTypeName(it);

        switch (it.mangling) with (NameMangling) {
        case Callback:
            hdr_pub.method(false, tn.type.str, "GetCallback", false);
            hdr_pub.method(false, "void", "SetCallback", false, tn.type.str ~ " value");
            break;
        case CallCounter:
            hdr_pub.method(false, tn.type.str, "GetCallCounter", true);
            hdr_pub.method(false, "void", "ResetCallCounter", false);
            break;
        case ReturnType:
            hdr_pub.method(false, tn.type.str ~ "&", "SetReturn", false);
            break;
        default:
            hdr_pub.method(false, tn.type.str, get_method.str, false);
        }

        hdr_priv.stmt(format("%s %s", tn.type.str, tn.name.str));
    }

    /// ditto
    private void renderGetSetImpl(T0)(InternalType it, const StubNs data_ns,
        const CppClassName stub_data_name, const CppMethodName get_method,
        const CppMethodName set_method, ref T0 impl) const {
        TypeName tn = InternalToTypeName(it);

        switch (it.mangling) with (NameMangling) {
        case Callback:
            with (impl.method_body(tn.type.str, stub_data_name.str, "GetCallback",
                    false)) {
                return_(tn.name.str);
            }
            impl.sep(2);
            with (impl.method_body("void", stub_data_name.str, "SetCallback",
                    false, tn.type.str ~ " value")) {
                stmt(E(tn.name.str) = E("value"));
            }
            impl.sep(2);
            break;
        case CallCounter:
            with (impl.method_body(tn.type.str, stub_data_name.str, "GetCallCounter",
                    true)) {
                return_(tn.name.str);
            }
            impl.sep(2);
            with (impl.method_body("void", stub_data_name.str, "ResetCallCounter",
                    false)) {
                stmt(E(tn.name.str) = E("0"));
            }
            impl.sep(2);
            break;
        case ReturnType:
            with (impl.method_body(tn.type.str ~ "&", stub_data_name.str, "SetReturn",
                    false)) {
                return_(tn.name.str);
            }
            impl.sep(2);
            break;
        default:
            with (impl.method_body(tn.type.str, stub_data_name.str, get_method.str,
                    false)) {
                return_(tn.name.str);
            }
            impl.sep(2);
        }
    }

    /** Render function and variable for a group.
     * Functions are:
     *  ns_internal::StubFunc& func()
     * Variables are:
     *  ns_internal::StubFunc varname
     *
     * ns_internal is dependent on the stub prefix and method the group belong to.
     * varname is whatever was put in the container.
     */
    private void renderDataFunc(T0, T1, T2)(CppMethodName group, ref T0 hdr_pub,
        ref T1 hdr_priv, ref T2 impl) const {
        import std.algorithm : find;

        //TODO refactor container to not need this check. Braindead...
        auto internal = vars.find!(a => a.mangling == NameMangling.Callback && a.group == group);
        if (internal.length == 0) {
            logger.errorf("No callback variable for group '%s'", group.str);
            return;
        }
        auto tn = internal[0].typename;

        auto struct_type = mangleToStubStructType(stub_prefix, group, class_name);
        auto variable = mangleToStubDataClassInternalVariable(stub_prefix,
            CppMethodName(tn.name.str));

        hdr_pub.method(false, struct_type.str ~ "&", tn.name.str, false);
        hdr_priv.stmt(E(struct_type.str) ~ E(variable.str));

        auto data_name = mangleToStubDataClass(stub_prefix);
        with (impl.method_body(struct_type.str ~ "&", data_name.str, tn.name.str, false)) {
            return_(variable.str);
        }
        impl.sep(2);
    }

private:
    TypeName InternalToTypeName(InternalType it) pure @safe nothrow const {
        TypeName tn;

        tn.name = mangleToStubStructMember(stub_prefix_lower, it.mangling, tn.name);

        final switch (it.mangling) with (NameMangling) {
        case Plain:
            return it.typename;
        case Callback:
            tn.type = cb_ns ~ "::" ~ cb_prefix ~ it.typename.type ~ "*";
            return tn;
        case CallCounter:
            tn.type = it.typename.type;
            return tn;
        case ReturnType:
            tn.type = it.typename.type;
            return tn;
        }
    }

    /// Init function for a struct of data.
    void renderInit(T0, T1, T2)(TypeName tn, CppMethodName method, ref T0 hdr,
        ref T1 impl, ref T2 ctor_init_impl) const {
        void doHeader(TypeName tn, ref T0 hdr) {
            hdr.func("void", "StubInit", format("%s* %s", tn.type.str, tn.name.str));
            hdr.sep(2);
        }

        void doImpl(TypeName tn, ref T1 impl, ref T1 ctor_init_impl) {
            auto init_func = stub_prefix.str ~ "Init";

            auto f = impl.func_body("void", init_func, tn.type ~ "* " ~ tn.name);
            with (f) {
                stmt(E("char* d") = E("reinterpret_cast<char*>")(tn.name.str));
                stmt(E("char* end") = E("d") + E("sizeof")(tn.type.str));
                with (for_("", "d != end", "++d")) {
                    stmt(E("*d") = 0);
                }
            }
            impl.sep(2);

            ctor_init_impl.stmt(
                E(init_func)("&" ~ mangleToStubDataClassInternalVariable(stub_prefix,
                method).str));
        }

        doHeader(tn, hdr);
        doImpl(tn, impl, ctor_init_impl);
    }

    alias InternalType = Tuple!(NameMangling, "mangling", TypeName, "typename",
        CppMethodName, "group");
    InternalType[] vars;
    CppMethodName[] groups;

    immutable StubPrefix stub_prefix;
    immutable StubPrefix stub_prefix_lower;
    immutable CallbackNs cb_ns;
    immutable CallbackPrefix cb_prefix;
    immutable StubNs data_ns;
    immutable CppClassName class_name;
}

/// Container of functions to generate callbacks for.
struct CallbackContainer {
    @disable this();

    /**
     * Params:
     *  cb_ns = namespace containing generated code for callbacks.
     *  cprefix = prefix for callback interfaces.
     */
    this(CallbackNs cb_ns, CallbackPrefix cprefix) {
        this.cb_ns = cb_ns;
        this.cprefix = cprefix;
    }

    /** Add a callback to the container.
     * Params:
     *  return_type = return type of the method.
     *  method = method name of the callback.
     *  params = parameters the method callback shall accept.
     */
    void push(CppType return_type, CppMethodName method, const TypeName[] params) {
        items ~= CallbackType(return_type, method, params.dup);
    }

    /** Add a callback to the container.
     * Params:
     *  return_type = return type of the method.
     *  method = method name of the callback.
     *  params = parameters the method callback shall accept.
     */
    void push(CppType return_type, CppMethodName method, const TypeKindVariable[] params) {
        import std.algorithm : map;
        import std.array : array;

        TypeName[] tmp = params.map!(a => TypeName(CppType(a.type.toString), a.name)).array();

        items ~= CallbackType(return_type, method, tmp);
    }

    ///TODO change to using an ID for the method.
    /// One proposal is to traverse the function inherit hierarchy to find the root.
    bool exists(CppMethodName method, const TypeName[] params) {
        import std.algorithm : any;

        string p = params.toString;

        return items.any!(a => a.name == method && a.params.toString == p);
    }

    @property auto length() {
        return items.length;
    }

    /** Generate the C++ interface for the callback.
     * Example:
     * ---
     * struct Ifunc1 { virtual int func1() = 0; };
     * ---
     *
     * Params:
     *  hdr = code module to inject the interface declaration in.
     */
    void renderInterfaces(ref CppModule hdr) {
        if (length == 0)
            return;

        auto ns_hdr = hdr.namespace(cb_ns.str);
        ns_hdr.suppressThisIndent(1);
        ns_hdr.suppressIndent(1);
        foreach (c; items) {
            auto s = ns_hdr.struct_(cprefix.str ~ c.name.str)[$.begin = " { "];
            // can't use convenient method function because it inserts a line break before };
            auto m = s.stmt(format("virtual %s %s(%s)", c.return_type.str,
                c.name.str, c.params.toString), false);
            m[$.begin = "", $.end = " = 0; "];
            m.suppressThisIndent(1);
        }

        hdr.sep(2);
    }

private:
    alias CallbackType = Tuple!(CppType, "return_type", CppMethodName,
        "name", TypeName[], "params");
    CallbackType[] items;
    CallbackNs cb_ns;
    CallbackPrefix cprefix;
}

@name("Test CallbackContainer length")
unittest {
    CallbackContainer cb = CallbackContainer(CallbackNs("foo"), CallbackPrefix("Stub"));
    assert(cb.length == 0, "expected 0, actual " ~ to!string(cb.length));

    cb.push(CppType("void"), CppMethodName("smurf"), TypeName[].init);
    assert(cb.length == 1, "expected 1, actual " ~ to!string(cb.length));
}

@name("Test CallbackContainer exists")
unittest {
    CallbackContainer cb = CallbackContainer(CallbackNs("foo"), CallbackPrefix("Stub"));
    cb.push(CppType("void"), CppMethodName("smurf"), TypeName[].init);

    assert(cb.exists(CppMethodName("smurf"), TypeName[].init), "expected true");
}

@name("Test CallbackContainer rendering")
unittest {
    CallbackContainer cb = CallbackContainer(CallbackNs("Foo"), CallbackPrefix("Stub"));

    cb.push(CppType("void"), CppMethodName("smurf"), TypeName[].init);
    auto m = new CppModule;

    cb.renderInterfaces(m);

    auto rval = m.render;
    auto exp = "namespace Foo {
struct Stubsmurf { virtual void smurf() = 0; };
} //NS:Foo

";

    assert(rval == exp, rval);
}
