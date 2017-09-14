/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.plugin.backend.cpptestdouble.adapter;

import std.typecons : Yes, No;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import dextool.type : MainNs, MainInterface;

// TODO this is a mega include. Reduce it.
import cpptooling.data;

import cpptooling.data : CppClass, CppNamespace, CppClassName, CppMethodName,
    USRType;

// dfmt off
@safe:
private struct BuildAdapter {
    BuildAdapter makeTestDouble(bool value) {
        this.hasTestDouble = value;
        return this;
    }

    BuildAdapter makeInitGlobals(bool value) {
        this.hasGlobalInitializer = value;
        return this;
    }

    CppClass finalize() {
        import cpptooling.data : SimpleFmt, TypeId, PtrFmt;

        auto c = CppClass(className);

        CxParam[] params;

        if (hasTestDouble) {
            auto attr = TypeAttr.init;
            attr.isRef = Yes.isRef;
            auto kind = TypeKind(TypeKind.PointerInfo(PtrFmt(TypeId(interfaceName)),
                    USRType(interfaceName ~ "&"), [attr]));

            params ~= makeCxParam(TypeKindVariable(TypeKindAttr(kind,
                    TypeAttr.init), CppVariable("inst")));
        }

        if (hasGlobalInitializer) {
            auto kind = TypeKind(TypeKind.SimpleInfo(SimpleFmt(TypeId(interfaceInitGlobal))));
            params ~= makeCxParam(TypeKindVariable(TypeKindAttr(kind,
                    TypeAttr.init), CppVariable("init_globals")));
        }

        c.comment("Adapter connecting an interface with an implementation.");
        c.comment("The lifetime of the connection is the same as the instance of the adapter.");

        c.put(CppCtor(makeUniqueUSR, classCtor, params, CppAccess(AccessType.Public)));
        c.put(CppDtor(makeUniqueUSR, classDtor, CppAccess(AccessType.Public),
                CppVirtualMethod(MemberVirtualType.Normal)));

        return c;
    }

private:
    CppClassName className;
    CppClassName interfaceName;
    CppClassName interfaceInitGlobal;
    CppMethodName classCtor;
    CppMethodName classDtor;
    bool hasTestDouble;
    bool hasGlobalInitializer;
}
// dfmt on

/// Make a C++ adapter for an interface.
BuildAdapter makeAdapter(InterfaceT)(InterfaceT interface_name) {
    return BuildAdapter(CppClassName("Adapter"), CppClassName(cast(string) interface_name),
            CppClassName(cast(string) interface_name ~ "_InitGlobals"),
            CppMethodName("Adapter"), CppMethodName("~Adapter"));
}

/// make an anonymous namespace containing a ptr to an instance of a test
/// double that implement the interface needed.
CppNamespace makeSingleton(MainNs main_ns, MainInterface main_if) {
    import cpptooling.data : CppVariable, CxGlobalVariable, makeUniqueUSR;
    import cpptooling.data : TypeId, PtrFmt;

    auto attr = TypeAttr.init;
    attr.isPtr = Yes.isPtr;
    auto kind = TypeKind(TypeKind.PointerInfo(PtrFmt(TypeId(main_ns ~ "::" ~ main_if)),
            USRType(main_ns ~ "::" ~ main_if ~ "*"), [attr]));

    auto v = CxGlobalVariable(makeUniqueUSR, TypeKindAttr(kind, TypeAttr.init),
            CppVariable("test_double_inst"));
    auto ns = CppNamespace.makeAnonymous();
    ns.put(v);

    return ns;
}

/** Generate an adapter implementation.
 *
 * The global is expected to be named test_double_inst.
 */
void generateImpl(CppClass c, CppModule impl) {
    import std.variant : visit;
    import cpptooling.data;
    import dsrcgen.c : E;

    // C'tor is expected to have N params.
    // One of them must be named inst.
    static void genCtor(const ref CppClass c, const ref CppCtor m, CppModule impl) {
        // dfmt off
        TypeKindVariable p0 = () @trusted {
            import std.array;

            return m.paramRange().front.visit!(
                (TypeKindVariable tkv) => tkv,
                (TypeKindAttr tk) => TypeKindVariable(tk, CppVariable("inst")),
                (VariadicType vt) {
                    logger.error("Variadic c'tor not supported:", m.toString);
                    return TypeKindVariable(makeSimple("not supported"), CppVariable("not supported"));
                })();
        }();
        // dfmt on

        with (impl.ctor_body(m.name, E(p0.type.toStringDecl(p0.name)))) {
            stmt(E("test_double_inst") = E("&" ~ p0.name));
        }
        impl.sep(2);
    }

    static void genOp(const ref CppClass c, const ref CppMethodOp m, CppModule impl) {
        // not applicable
    }

    static void genDtor(const ref CppClass c, const ref CppDtor m, CppModule impl) {
        with (impl.dtor_body(c.name)) {
            stmt("test_double_inst = 0");
        }
        impl.sep(2);
    }

    static void genMethod(const ref CppClass c, const ref CppMethod m, CppModule impl) {
        import std.range : takeOne;

        string params = m.paramRange().joinParams();
        auto b = impl.method_body(m.returnType.toStringDecl, c.name, m.name,
                m.isConst ? Yes.isConst : No.isConst, params);
        with (b) {
            auto p = m.paramRange().joinParamNames();
            stmt(E("test_double_inst") = E("&" ~ p));
        }
        impl.sep(2);
    }

    foreach (m; c.methodPublicRange()) {
        // dfmt off
        () @trusted{
            m.visit!(
                (const CppMethod m) => genMethod(c, m, impl),
                (const CppMethodOp m) => genOp(c, m, impl),
                (const CppCtor m) => genCtor(c, m, impl),
                (const CppDtor m) => genDtor(c, m, impl));
        }();
        // dfmt on
    }
}

/// A singleton to allow the adapter to setup "a" connection.
void generateSingleton(CppNamespace in_ns, CppModule impl) {
    import std.ascii : newline;
    import cpptooling.data;
    import dsrcgen.cpp : E;

    auto ns = impl.namespace("")[$.begin = "{" ~ newline];
    ns.suppressIndent(1);
    impl.sep(2);

    foreach (g; in_ns.globalRange()) {
        auto stmt = E(g.type.toStringDecl(g.name));
        if (g.type.kind.info.kind == TypeKind.Info.Kind.pointer) {
            stmt = E("0");
        }
        ns.stmt(stmt);
    }
}
