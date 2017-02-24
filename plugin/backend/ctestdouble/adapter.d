/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module plugin.backend.ctestdouble.adapter;

import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import dextool.type : StubPrefix;
import cpptooling.data.representation : CppClass, CppClassName, CppNamespace,
    CppNs;
import plugin.backend.ctestdouble.global : MutableGlobal;

@safe:

/// The kind of constructors the adapters ctor can be. Affects the generated
/// code.
enum AdapterKind {
    none,
    ctor_initGlobal,
    ctor_testDouble,
    ctor_testDouble_zeroGlobal,
    ctor_testDouble_initGlobal,
    dtor_empty,
    dtor_testDouble,
}

private struct BuildAdapter {
    import cpptooling.data.representation : CppClass, CppClassName,
        CppMethodName;

    private {
        CppClassName className;
        CppClassName interfaceName;
        CppClassName interfaceInitGlobal;
        CppMethodName classCtor;
        CppMethodName classDtor;
        bool hasTestDouble;
        bool hasGlobalInitializer;
    }

    BuildAdapter makeTestDouble(bool value) {
        this.hasTestDouble = value;
        return this;
    }

    BuildAdapter makeInitGlobals(bool value) {
        this.hasGlobalInitializer = value;
        return this;
    }

    /** Finalize the construction of a class representation the adapter.
     *
     * Additional metadata about the kinds the adapters c'tor and d'tor is.
     * Used for code generation.
     */
    CppClass finalize(ImplDataT)(ref ImplDataT data) {
        import std.typecons : Yes;
        import cpptooling.data.representation : AccessType, CxParam, CppCtor,
            CppDtor, CppAccess, CppVirtualMethod, CppVariable, makeUniqueUSR,
            makeCxParam, MemberVirtualType, TypeAttr, TypeKind, TypeKindAttr,
            TypeKindVariable;

        auto c = CppClass(className);
        c.comment("Adapter connecting an interface with an implementation.");
        c.comment("The lifetime of the connection is the same as the instance of the adapter.");

        CxParam[] params;

        if (hasTestDouble) {
            auto attr = TypeAttr.init;
            attr.isRef = Yes.isRef;
            auto kind = TypeKind(TypeKind.PointerInfo(interfaceName ~ "%s %s",
                    makeUniqueUSR, [attr]));

            params ~= makeCxParam(TypeKindVariable(TypeKindAttr(kind,
                    TypeAttr.init), CppVariable("inst")));
        }

        if (hasGlobalInitializer) {
            auto attr = TypeAttr.init;
            attr.isRef = Yes.isRef;
            auto kind = TypeKind(TypeKind.PointerInfo(interfaceInitGlobal ~ "%s %s",
                    makeUniqueUSR, [attr]));
            params ~= makeCxParam(TypeKindVariable(TypeKindAttr(kind,
                    TypeAttr.init), CppVariable("init_globals")));
        }

        if (params.length != 0) {
            auto ctor = CppCtor(makeUniqueUSR, classCtor, params[0 .. 1],
                    CppAccess(AccessType.Public));
            c.put(ctor);

            if (hasTestDouble && hasGlobalInitializer) {
                data.adapterKind[ctor.usr] = AdapterKind.ctor_testDouble_zeroGlobal;
            } else if (hasGlobalInitializer) {
                data.adapterKind[ctor.usr] = AdapterKind.ctor_initGlobal;
            } else if (hasTestDouble) {
                data.adapterKind[ctor.usr] = AdapterKind.ctor_testDouble;
            }
        }
        if (params.length == 2) {
            auto ctor = CppCtor(makeUniqueUSR, classCtor, params, CppAccess(AccessType.Public));
            c.put(ctor);
            data.adapterKind[ctor.usr] = AdapterKind.ctor_testDouble_initGlobal;
        }

        auto dtor = CppDtor(makeUniqueUSR, classDtor, CppAccess(AccessType.Public),
                CppVirtualMethod(MemberVirtualType.Normal));
        c.put(dtor);
        if (hasTestDouble) {
            data.adapterKind[dtor.usr] = AdapterKind.dtor_testDouble;
        } else {
            data.adapterKind[dtor.usr] = AdapterKind.dtor_empty;
        }

        return c;
    }
}

/// Make a C++ adapter for an interface.
auto makeAdapter(InterfaceT)(InterfaceT interface_name) {
    import cpptooling.data.representation : CppMethodName;

    return BuildAdapter(CppClassName("Adapter"), CppClassName(cast(string) interface_name),
            CppClassName(cast(string) interface_name ~ "_InitGlobals"),
            CppMethodName("Adapter"), CppMethodName("~Adapter"));
}

/// make an anonymous namespace containing a ptr to an instance of a test
/// double that implement the interface needed.
CppNamespace makeSingleton(CppNs namespace_name, CppClassName type_name, string instance_name) {
    import std.typecons : Yes;
    import cpptooling.data.representation : CppVariable, CxGlobalVariable,
        makeUniqueUSR, TypeAttr, TypeKind, USRType, TypeKindAttr;

    auto attr = TypeAttr.init;
    attr.isPtr = Yes.isPtr;
    auto kind = TypeKind(TypeKind.PointerInfo(namespace_name ~ "::" ~ type_name ~ "%s %s",
            USRType(namespace_name ~ "::" ~ type_name ~ "*"), [attr]));

    auto v = CxGlobalVariable(makeUniqueUSR, TypeKindAttr(kind, TypeAttr.init),
            CppVariable(instance_name));
    auto ns = CppNamespace.makeAnonymous();
    ns.put(v);

    return ns;
}

/** Generate an adapter implementation.
 *
 * The global is expected to be named test_double_inst.
 */
void generateImpl(LookupKindT)(CppClass adapter, MutableGlobal[] globals,
        StubPrefix prefix, CppModule impl, LookupKindT lookup) {
    import std.variant : visit;
    import cpptooling.data.representation;
    import dsrcgen.c : E;

    static void genCallsToGlobalInitializer(MutableGlobal[] globals,
            CppVariable instance, CppModule impl) {
        import cpptooling.data.representation : methodNameToString;

        foreach (global; globals) {
            impl.stmt(E(instance).e(global.name)(""));
        }
    }

    void genCtor(const ref CppClass adapter, const ref CppCtor m, CppModule impl) {
        import dsrcgen.cpp;
        import cpptooling.data.representation;
        import cpptooling.analyzer.type : TypeKind;

        AdapterKind kind;
        if (auto l = lookup(m.usr)) {
            kind = *l;
        } else {
            logger.error("c'tor for the adapter is corrupted");
            return;
        }

        string params = m.paramRange().joinParams();
        auto body_ = impl.ctor_body(m.name, params);

        switch (kind) with (AdapterKind) {
        case ctor_initGlobal:
            genCallsToGlobalInitializer(globals,
                    CppVariable(m.paramRange[0].paramNameToString), body_);
            break;
        case ctor_testDouble:
            body_.stmt(E("test_double_inst") = E("&" ~ m.paramRange[0].paramNameToString));
            break;
        case ctor_testDouble_zeroGlobal:
            body_.stmt(E("test_double_inst") = E("&" ~ m.paramRange[0].paramNameToString));
            body_.stmt(prefix ~ "ZeroGlobals" ~ " init_globals");
            genCallsToGlobalInitializer(globals, CppVariable("init_globals"), body_);
            break;
        case ctor_testDouble_initGlobal:
            body_.stmt(E("test_double_inst") = E("&" ~ m.paramRange[0].paramNameToString));
            genCallsToGlobalInitializer(globals,
                    CppVariable(m.paramRange[1].paramNameToString), body_);
            break;
        default:
            assert(0);
        }

        impl.sep(2);
    }

    static void genOp(const ref CppClass adapter, const ref CppMethodOp m, CppModule impl) {
        // not applicable
    }

    void genDtor(const ref CppClass adapter, const ref CppDtor m, CppModule impl) {
        AdapterKind kind;
        if (auto l = lookup(m.usr)) {
            kind = *l;
        } else {
            logger.error("d'tor for the adapter is corrupted");
            return;
        }

        switch (kind) with (AdapterKind) {
        case dtor_empty:
            impl.dtor_body(adapter.name);
            break;
        case dtor_testDouble:
            with (impl.dtor_body(adapter.name)) {
                stmt("test_double_inst = 0");
            }
            break;
        default:
            assert(0);
        }

        impl.sep(2);
    }

    static void genMethod(const ref CppClass adapter, const ref CppMethod m, CppModule impl) {
        import std.range : takeOne;
        import std.typecons : Yes, No;
        import cpptooling.analyzer.type : toStringDecl;

        string params = m.paramRange().joinParams();
        auto b = impl.method_body(m.returnType.toStringDecl, adapter.name,
                m.name, m.isConst ? Yes.isConst : No.isConst, params);
        with (b) {
            auto p = m.paramRange().joinParamNames();
            stmt(E("test_double_inst") = E("&" ~ p));
        }
        impl.sep(2);
    }

    foreach (m; adapter.methodPublicRange()) {
        // dfmt off
        () @trusted{
            m.visit!(
                (const CppMethod m) => genMethod(adapter, m, impl),
                (const CppMethodOp m) => genOp(adapter, m, impl),
                (const CppCtor m) => genCtor(adapter, m, impl),
                (const CppDtor m) => genDtor(adapter, m, impl));
        }();
        // dfmt on
    }
}

/// A singleton to allow the adapter to setup "a" connection.
void generateSingleton(CppNamespace in_ns, CppModule impl) {
    import std.ascii : newline;
    import cpptooling.analyzer.type;
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
