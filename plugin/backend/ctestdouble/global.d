/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.backend.ctestdouble.global;

import application.types : StubPrefix;
import cpptooling.analyzer.type : TypeKind;
import cpptooling.data.representation : CppClass, CppClassName, CppInherit,
    CxGlobalVariable;
import cpptooling.data.symbol.types : USRType;
import cpptooling.data.symbol.container : Container;
import dsrcgen.cpp : CppModule;

import logger = std.experimental.logger;

struct MutableGlobal {
    CxGlobalVariable mutable;
    TypeKind underlying;

    alias mutable this;
}

/// Recursive lookup until the underlying type is found.
TypeKind resolveTypedef(TypeKind type, const ref Container container) @safe nothrow {
    TypeKind rval = type;
    auto found = typeof(container.find!TypeKind(USRType.init)).init;

    switch (type.info.kind) with (TypeKind.Info) {
    case Kind.typeRef:
        found = container.find!TypeKind(type.info.canonicalRef);
        break;
    default:
        break;
    }

    foreach (item; found) {
        rval = item;
    }

    if (rval.info.kind == TypeKind.Info.Kind.typeRef) {
        return resolveTypedef(rval, container);
    }

    return rval;
}

auto filterMutable(RangeT)(RangeT range, const ref Container container) {
    import std.algorithm : filter, map;
    import std.range : ElementType;
    import std.range : tee;

    static bool isNotConst(ref ElementType!RangeT element) {
        auto info = element.type.kind.info;

        switch (info.kind) with (TypeKind.Info) {
        case Kind.funcPtr:
            goto case;
        case Kind.pointer:
            // every pointer have at least one attribute.
            // because the attribute is for the pointer itself.
            assert(info.attrs.length != 0);
            return !info.attrs[$ - 1].isConst;
        default:
            break;
        }

        return !element.type.attr.isConst;
    }

    return range.filter!(a => isNotConst(a)).map!(a => MutableGlobal(a,
            resolveTypedef(a.type.kind, container))).tee!(a => logger.info(a.type.kind.usr));
}

/** Make a C++ "interface" class of all mutable globals.
 *
 * The range must NOT contain any const globals.
 */
CppClass makeGlobalInterface(RangeT)(RangeT range, const CppClassName main_if) @safe {
    import std.algorithm : filter, map;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type : makeSimple;

    auto globals_if = CppClass(main_if);
    globals_if.put(CppDtor(makeUniqueUSR, CppMethodName("~" ~ globals_if.name),
            CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual)));

    const void_ = CxReturnType(makeSimple("void"));

    foreach (a; range) {
        auto method = CppMethod(a.usr, CppMethodName(a.name), CxParam[].init,
                void_, CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Pure));
        globals_if.put(method);
    }

    return globals_if;
}

/// The range must NOT contain any const globals.
CppClass makeZeroGlobal(RangeT)(RangeT range, const CppClassName main_if,
        const StubPrefix prefix, CppInherit inherit) @safe {
    import std.algorithm : filter, map;
    import cpptooling.analyzer.kind : TypeKind, isIncompleteArray;
    import cpptooling.analyzer.type : makeSimple;
    import cpptooling.data.representation;

    auto globals_if = CppClass(main_if, [inherit]);
    globals_if.put(CppCtor(USRType(globals_if.name), CppMethodName(globals_if.name),
            CxParam[].init, CppAccess(AccessType.Public)));
    globals_if.put(CppDtor(USRType("~" ~ globals_if.name),
            CppMethodName("~" ~ globals_if.name), CppAccess(AccessType.Public),
            CppVirtualMethod(MemberVirtualType.Virtual)));

    const void_ = CxReturnType(makeSimple("void"));

    foreach (a; range) {
        auto method = CppMethod(a.usr, CppMethodName(a.name), CxParam[].init,
                void_, CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Virtual));

        switch (a.underlying.info.kind) with (TypeKind.Info) {
        case Kind.array:
            if (isIncompleteArray(a.type.kind.info.indexes)) {
                method.comment("Warning: Incomplete array, unable to generate an initializer.");
            }
            break;
        default:
        }

        globals_if.put(method);
    }

    return globals_if;
}

/** Generate an implementation of InitGlobal that initialize all globals to zero.
 *
 * It thus emulates what the compiler do with the .bss-segment during cbegin.
 */
void generateInitGlobalsToZero(LookupGlobalT)(ref CppClass c, CppModule impl,
        const StubPrefix prefix, LookupGlobalT lookup) @safe {
    import std.typecons : No;
    import std.variant : visit;
    import cpptooling.data.representation;
    import dsrcgen.c : E;

    static void noop() {
    }

    static void genCtor(CppClassName name, CppModule impl) {
        impl.ctor_body(name);
        impl.sep(2);
    }

    static void genDtor(CppClassName name, CppModule impl) {
        impl.dtor_body(name);
        impl.sep(2);
    }

    void genMethod(const ref CppClass c, const ref CppMethod m,
            const StubPrefix prefix, CppModule impl, ref bool need_memzero) {
        import std.range : takeOne;

        static import std.format;
        import cpptooling.analyzer.kind : TypeKind, isIncompleteArray;

        auto fqn = "::" ~ m.name;
        auto body_ = impl.method_body("void", c.name, m.name, No.isConst);
        auto global = lookup(m.name);

        switch (global.underlying.info.kind) with (TypeKind.Info) {
        case Kind.array:
            if (isIncompleteArray(global.type.kind.info.indexes)) {
                // may be possible to initialize it to zero by casting to pointers?
            } else {
                // c-style cast needed. the compiler warnings about throwning away the const qualifiers otherwise.
                body_.stmt(E(prefix ~ "memzero")(std.format.format("(void*)(%s), %s",
                        fqn, E("sizeof")(fqn))));
                need_memzero = true;
            }
            break;

        case Kind.primitive:
            if (global.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
                // may be a typedef of an array which is classified as a
                // prmitive. This is a bug. Fix clang/type.d to resolve the
                // intermediate node as an array.
                body_.stmt(E(prefix ~ "memzero")(std.format.format("&%s, %s",
                        fqn, E("sizeof")(fqn))));
                need_memzero = true;
            } else {
                body_.stmt(E(fqn) = E(0));
            }
            break;

        case Kind.funcPtr:
            goto case;
        case Kind.pointer:
            body_.stmt(E(fqn) = E(0));
            break;

        default:
            body_.stmt(E(prefix ~ "memzero")(std.format.format("&%s, %s", fqn, E("sizeof")(fqn))));
            need_memzero = true;
        }

        impl.sep(2);
    }

    auto memzero_hook = impl.base;
    memzero_hook.suppressIndent(1);
    auto memzero = new CppModule;
    memzero.suppressIndent(1);

    with (memzero.func_body("void", prefix ~ "memzero", "void* s", "unsigned int n")) {
        stmt("char* iter = reinterpret_cast<char*>(s)");
        stmt("char* end = reinterpret_cast<char*>(s) + n");

        // overflow check that isn't an undefinied behavior.
        // why this implementation and not another?
        // if (ptr + len < ptr || ptr + len > max) ..;
        // The first part would be removed because the compiler can prove that
        // it invokes UB.

        comment("crash if the address ptr overflows");
        with (if_("n > end - iter")) {
            stmt("*((char*) -1) = 'x'");
            stmt("return");
        }
        with (for_("", "iter < end", "++iter")) {
            stmt("*iter = 0");
        }
    }

    bool need_memzero;
    foreach (m; c.methodPublicRange()) {
        // dfmt off
        () @trusted{
            m.visit!(
                (const CppMethod m) => genMethod(c, m, prefix, impl, need_memzero),
                (const CppMethodOp m) => noop,
                (const CppCtor m) => genCtor(c.name, impl),
                (const CppDtor m) => genDtor(c.name, impl));
        }();
        // dfmt on
    }

    if (need_memzero) {
        memzero_hook.append(memzero);
        memzero_hook.sep(1);
    }
}

@("Should be an interface of globals")
unittest {
    import std.array;
    import test.extra_should : shouldEqualPretty;
    import cpptooling.data.representation;
    import cpptooling.data.type;
    import cpptooling.analyzer.type;

    immutable dummyUSR = USRType("dummyUSR1");

    auto v0 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));

    auto if_ = makeGlobalInterface([v0], CppClassName("TestDouble"));

    if_.toString.shouldEqualPretty("class TestDouble { // Pure
public:
  virtual ~TestDouble();
  virtual void x() = 0;
}; //Class:TestDouble");
}
