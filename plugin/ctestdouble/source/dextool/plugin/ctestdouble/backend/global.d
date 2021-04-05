/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.ctestdouble.backend.global;

import dsrcgen.cpp : CppModule;
import my.sumtype;

import cpptooling.type : StubPrefix;
import cpptooling.data : CppClass, CppClassName, CppInherit, CppVariable,
    CxGlobalVariable, TypeKindAttr, USRType, TypeKind, Void;
import cpptooling.data.symbol : Container;

import logger = std.experimental.logger;

version (unittest) {
    import unit_threaded.assertions : shouldEqual;
}

struct MutableGlobal {
    CxGlobalVariable mutable;
    TypeKind underlying;

    alias mutable this;
}

/// Recursive lookup until the underlying type is found.
TypeKind resolveTypedef(TypeKind type, ref Container container) @trusted nothrow {
    TypeKind rval = type;
    auto found = typeof(container.find!TypeKind(USRType.init)).init;

    type.info.match!((TypeKind.TypeRefInfo t) {
        found = container.find!TypeKind(t.canonicalRef);
    }, (_) {});

    foreach (item; found)
        rval = item;

    return rval.info.match!((TypeKind.TypeRefInfo t) => resolveTypedef(rval, container), _ => rval);
}

auto filterMutable(RangeT)(RangeT range, ref Container container) {
    import std.algorithm : filter, map;
    import std.range : ElementType;
    import std.range : tee;

    static bool isNotConst(ref ElementType!RangeT element) {
        auto info = element.type.kind.info;

        bool handler(T)(ref T info) {
            // every pointer have at least one attribute.
            // because the attribute is for the pointer itself.
            assert(info.attrs.length != 0);
            return !info.attrs[$ - 1].isConst;
        }

        return info.match!((const TypeKind.FuncPtrInfo t) => handler(t),
                (const TypeKind.PointerInfo t) => handler(t), _ => !element.type.attr.isConst);
    }

    resolveTypedef(range.front.type.kind, container);

    return range.filter!(a => isNotConst(a))
        .map!(a => MutableGlobal(a, resolveTypedef(a.type.kind, container)));
}

/** Make a C++ "interface" class of all mutable globals.
 *
 * The range must NOT contain any const globals.
 */
CppClass makeGlobalInterface(RangeT)(RangeT range, CppClassName main_if) @safe {
    import std.algorithm : filter, map;
    import cpptooling.data;
    import cpptooling.data : makeSimple;

    auto globals_if = CppClass(main_if);
    globals_if.put(CppDtor(makeUniqueUSR, CppMethodName("~" ~ globals_if.name),
            CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual)));

    auto void_ = CxReturnType(makeSimple("void"));

    foreach (a; range) {
        auto method = CppMethod(a.usr.get, CppMethodName(a.name), CxParam[].init,
                void_, CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Pure));
        globals_if.put(method);
    }

    return globals_if;
}

/// The range must NOT contain any const globals.
CppClass makeZeroGlobal(RangeT)(RangeT range, CppClassName main_if,
        StubPrefix prefix, CppInherit inherit) @safe {
    import std.algorithm : filter, map;
    import cpptooling.data : TypeKind, isIncompleteArray, makeSimple;
    import cpptooling.data;

    auto globals_if = CppClass(main_if, [inherit]);
    globals_if.comment("Initialize all global variables that are mutable to zero.");

    globals_if.put(CppCtor(USRType(globals_if.name), CppMethodName(globals_if.name),
            CxParam[].init, CppAccess(AccessType.Public)));
    globals_if.put(CppDtor(USRType("~" ~ globals_if.name),
            CppMethodName("~" ~ globals_if.name), CppAccess(AccessType.Public),
            CppVirtualMethod(MemberVirtualType.Virtual)));

    auto void_ = CxReturnType(makeSimple("void"));

    foreach (a; range) {
        auto method = CppMethod(a.usr.get, CppMethodName(a.name), CxParam[].init,
                void_, CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Virtual));

        globals_if.put(method);
    }

    return globals_if;
}

/** Generate an implementation of InitGlobal that initialize all globals to zero.
 *
 * It thus emulates what the compiler do with the .bss-segment during cbegin.
 */
void generateInitGlobalsToZero(LookupGlobalT)(ref CppClass c, CppModule impl,
        StubPrefix prefix, LookupGlobalT lookup) @safe {
    import std.typecons : No;
    import std.variant : visit;
    import cpptooling.data : CppMethod, CppMethodOp, CppCtor, CppDtor;
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

    void genMethod(ref CppClass c, ref CppMethod m, StubPrefix prefix,
            CppModule impl, ref bool need_memzero) {
        import std.range : takeOne;

        static import std.format;
        import cpptooling.data : TypeKind, isIncompleteArray;

        auto fqn = "::" ~ m.name;
        auto body_ = impl.method_body("void", c.name, m.name, No.isConst);
        auto global = lookup(m.name);

        global.underlying.info.match!((TypeKind.ArrayInfo t) {
            if (isIncompleteArray(t.indexes)) {
                body_.stmt(E("void** ptr") = E("(void**) &" ~ fqn));
                body_.stmt("*ptr = 0");
            } else {
                // c-style cast needed. the compiler warnings about throwning away the const qualifiers otherwise.
                body_.stmt(E(prefix ~ "memzero")(std.format.format("(void*)(%s), %s",
                    fqn, E("sizeof")(fqn))));
                need_memzero = true;
            }
        }, (TypeKind.PrimitiveInfo t) {
            global.type.kind.info.match!((TypeKind.TypeRefInfo t) {
                // may be a typedef of an array which is classified as a
                // prmitive. This is a bug. Fix clang/type.d to resolve the
                // intermediate node as an array.
                body_.stmt(E(prefix ~ "memzero")(std.format.format("&%s, %s",
                fqn, E("sizeof")(fqn))));
                need_memzero = true;
            }, (_) { body_.stmt(E(fqn) = E(0)); });
        }, (TypeKind.FuncPtrInfo t) { body_.stmt(E(fqn) = E(0)); }, (TypeKind.PointerInfo t) {
            body_.stmt(E(fqn) = E(0));
        }, (_) {
            body_.stmt(E(prefix ~ "memzero")(std.format.format("&%s, %s", fqn, E("sizeof")(fqn))));
            need_memzero = true;
        });

        impl.sep(2);
    }

    void makeMemzero(CppModule hook) {
        hook.suppressIndent(1);
        auto memzero = hook.namespace("");
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

        hook.sep(2);
    }

    // need to create the hook before generating functions that may need it.
    auto memzero_hook = impl.base;

    bool need_memzero;
    foreach (m; c.methodPublicRange()) {
        // dfmt off
        () @trusted{
            m.visit!(
                (CppMethod m) => genMethod(c, m, prefix, impl, need_memzero),
                (CppMethodOp m) => noop,
                (CppCtor m) => genCtor(c.name, impl),
                (CppDtor m) => genDtor(c.name, impl));
        }();
        // dfmt on
    }

    if (need_memzero) {
        makeMemzero(memzero_hook);
    }
}

string variableToString(CppVariable name, TypeKindAttr type) @safe pure {
    import cpptooling.data : toStringDecl;

    // example: extern int extern_a[4];
    return type.kind.info.match!(restrictTo!(TypeKind.ArrayInfo, TypeKind.FuncPtrInfo,
            TypeKind.PointerInfo, TypeKind.PrimitiveInfo, TypeKind.RecordInfo,
            TypeKind.SimpleInfo, TypeKind.TypeRefInfo, (a) {
            return type.toStringDecl(name);
        }), restrictTo!(TypeKind.FuncInfo, TypeKind.FuncSignatureInfo,
            TypeKind.CtorInfo, TypeKind.DtorInfo, (a) {
            assert(0);
            return string.init;
        }), (Void a) {
        debug logger.errorf("Variable has type null_. USR:%s name:%s", type.kind.usr, name);
        return string.init;
    });
}

void generateGlobalExterns(RangeT)(RangeT range, CppModule impl, ref Container container) {
    import std.algorithm : map, joiner;

    auto externs = impl.base;
    externs.suppressIndent(1);
    externs.sep;
    impl.sep;

    foreach (ref global; range) {
        externs.stmt("extern " ~ variableToString(global.name, global.type));
    }
}

@("Should be an interface of globals")
unittest {
    import std.array;
    import cpptooling.data;

    immutable dummyUSR = USRType("dummyUSR1");

    auto v0 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));

    auto if_ = makeGlobalInterface([v0], CppClassName("TestDouble"));

    if_.toString.shouldEqual("class TestDouble { // Pure
public:
  virtual ~TestDouble();
  virtual void x() = 0;
}; //Class:TestDouble");
}
