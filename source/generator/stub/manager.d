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
module generator.stub.manager;

import std.typecons : BlackHole;

import logger = std.experimental.logger;

import dsrcgen.cpp;

import generator.stub.types;

import tested;

/// C++ pool for generated objects.
interface StubPool {
    void renderClass(CppModule hdr, CppModule impl);
    void renderRegisterFunc(CppModule hdr, CppModule impl);
    void renderRegister(const CppVariable var, CppModule impl);
    void renderUnRegister(const CppVariable var, CppModule impl);
}

version (unittest) {
    shared static this() {
        assert(runUnitTests!(generator.stub.manager)(new ConsoleTestResultWriter),
            "Unit tests failed.");
    }
}

/** Generated code for a manager that allows access and cleanup of registered
 * instances.
 *
 * A common use case is that the SUT creates instances internally via
 * dependency injection.The tester must gain access to those to control the
 * stimuli.
 */
class Manager : StubPool {
    @disable this();

    this(StubPrefix prefix, CppNsNesting ns_internal, PoolName name, CppType type) {
        this.prefix = prefix;
        this.name = name;
        this.type = type;
        this.ns_internal = ns_internal;

        register_func = prefix.str ~ prefix.str ~ "ManagerRegister";
        unregister_func = prefix.str ~ prefix.str ~ "ManagerUnRegister";
    }

    /// Render the manager class.
    void renderClass(CppModule hdr, CppModule impl) {
        renderClassHdr(name, type, hdr);
        renderClassImpl(name, type, ns_internal, impl);
    }

    /// Render the internal functions and variables to un/register an instance in the pool.
    void renderRegisterFunc(CppModule hdr, CppModule impl) {
        renderRegisterFuncHdr(prefix, type, hdr);
        renderRegisterFuncImpl(prefix, type, name, impl);
    }

    void renderRegister(const CppVariable var, CppModule impl) {
        impl.stmt(E(ns_internal.str ~ "::" ~ register_func)(var.str));
    }

    void renderUnRegister(const CppVariable var, CppModule impl) {
        impl.stmt(E(ns_internal.str ~ "::" ~ unregister_func)(var.str));
    }

private:
    immutable StubPrefix prefix;
    immutable PoolName name;
    immutable CppType type;
    immutable CppNsNesting ns_internal;

    immutable string register_func;
    immutable string unregister_func;
}

private:

void renderClassHdr(const PoolName name, const CppType type, CppModule hdr) {
    with (hdr.class_(name.str)) {
        with (public_) {
            ctor(name.str);
            dtor(name.str);
            sep(2);

            comment("Get the first instance created.")[$.begin = "/// "];
            comment("@return Pointer to instance or null if none is created.")[$.begin = "/// "];
            method(false, type.str ~ "*", "GetInstance", false);
            sep(2);

            comment("Get the Nth instance created.")[$.begin = "/// "];
            comment("@return Pointer to instance or null if none was found.")[$.begin = "/// "];
            method(false, type.str ~ "*", "GetInstance", false, "unsigned nth");
        }
    }
    hdr.sep(2);
}

void renderClassImpl(const PoolName name, const CppType type, CppNsNesting ns, CppModule impl) {
    import std.string : toLower;

    auto name_l = name.str.toLower;
    string manager_pool = ns.str ~ "::" ~ name_l ~ "_pool";
    string manager_size = ns.str ~ "::" ~ name_l ~ "_size";
    string manager_next = ns.str ~ "::" ~ name_l ~ "_next";

    with (impl.ctor_body(name.str)) {
    }
    impl.sep(2);

    with (impl.dtor_body(name.str)) {
        with (for_("unsigned i = 0", "i < " ~ manager_size, "++i")) {
            with (if_(manager_pool ~ "[i] != 0")) {
                delete_(manager_pool ~ "[i]");
            }
        }
        delete_array(manager_pool);
        stmt(E(manager_pool) = 0);
        stmt(E(manager_size) = 0);
        stmt(E(manager_next) = 0);
    }
    impl.sep(2);

    with (impl.method_body(type.str ~ "*", name.str, "GetInstance", false)) {
        with (if_(manager_size ~ " > 0")) {
            return_(E(manager_pool ~ "[0]"));
        }
        return_("reinterpret_cast< " ~ type.str ~ "*>(0)");
    }
    impl.sep(2);

    with (impl.method_body(type.str ~ "*", name.str, "GetInstance", false, E("unsigned nth"))) {
        with (if_(manager_size ~ " > nth")) {
            return_(E(manager_pool ~ "[nth]"));
        }
        return_("reinterpret_cast< " ~ type.str ~ "*>(0)");
    }
    impl.sep(2);
}

void renderRegisterFuncHdr(const StubPrefix prefix, const CppType type, CppModule hdr) {
    hdr.func("void", prefix.str ~ prefix.str ~ "ManagerRegister", E(type.str ~ "*") ~ E("instance"));
    hdr.func("void", prefix.str ~ prefix.str ~ "ManagerUnRegister", E(type.str ~ "*") ~ E(
        "instance"));
}

void renderRegisterFuncImpl(const StubPrefix prefix, const CppType type,
    const PoolName name, CppModule impl) {
    import std.string : toLower;

    auto name_l = name.str.toLower;
    string manager_pool = name_l ~ "_pool";
    string manager_size = name_l ~ "_size";
    string manager_next = name_l ~ "_next";
    string grow_func = prefix.str ~ prefix.str ~ "ManagerGrowPool";

    impl.stmt(E(type.str ~ "**") ~ E(manager_pool) = 0);
    impl.stmt(E("unsigned") ~ E(manager_size) = 0);
    impl.stmt(E("unsigned") ~ E(manager_next) = 0);
    impl.sep(2);

    with (impl.func_body("void", grow_func)) {
        with (if_(manager_pool ~ " == 0")) {
            stmt(E(manager_pool) = E("new " ~ type.str ~ "*[2]"));
            stmt(E(manager_size) = 2);
            stmt(E(manager_next) = 0);
        }
        with (else_) {
            stmt(E(type.str ~ "** old") = E(manager_pool));
            stmt(E("unsigned old_size") = E(manager_size));
            stmt(E(manager_size) = E(manager_size) * 2);
            stmt(E(manager_pool) = E("new " ~ type.str ~ "*[" ~ manager_size ~ "]"));
            with (for_("unsigned i = 0", "i < old_size", "++i")) {
                stmt(E(manager_pool ~ "[i]") = "old[i]");
            }
            delete_array("old");
        }
    }
    impl.sep(2);

    with (impl.func_body("void", prefix.str ~ prefix.str ~ "ManagerRegister",
            E(type.str ~ "*") ~ E("instance"))) {
        with (if_(manager_pool ~ " == 0 || " ~ manager_next ~ " == " ~ manager_size)) {
            stmt(E(grow_func)(""));
        }
        stmt(E(manager_pool ~ "[" ~ manager_next ~ "]") = "instance");
        stmt(manager_next ~ " += 1");
    }
    impl.sep(2);

    with (impl.func_body("void", prefix.str ~ prefix.str ~ "ManagerUnRegister",
            E(type.str ~ "*") ~ E("instance"))) {
        with (for_("unsigned i = 0", "i < " ~ manager_size, "++i")) {
            with (if_(manager_pool ~ "[i] == instance")) {
                stmt(manager_pool ~ "[i] = 0");
                break_;
            }
        }
    }
    impl.sep(2);
}

version (unittest) {
    mixin template TestFixture() {
        auto hdr = new CppModule;
        auto impl = new CppModule;
        auto m = new Manager(StubPrefix("Stub"),
            CppNsNesting("::StubInternalSimple"), PoolName("StubSimpleManager"), CppType("Simple"));

    }
}

@name("Test rendering of register declaration")
unittest {
    auto expect = "    void StubStubManagerRegister(Simple* instance);
    void StubStubManagerUnRegister(Simple* instance);
";
    mixin TestFixture;

    m.renderRegisterFunc(hdr, impl);
    auto r = hdr.render;
    assert(expect == r, r);
}

@name("Test rendering of register implementation")
unittest {
    auto expect = "    Simple** stubsimplemanager_pool = 0;
    unsigned stubsimplemanager_size = 0;
    unsigned stubsimplemanager_next = 0;

    void StubStubManagerGrowPool() {
        if (stubsimplemanager_pool == 0) {
            stubsimplemanager_pool = new Simple*[2];
            stubsimplemanager_size = 2;
            stubsimplemanager_next = 0;
        }
        else {
            Simple** old = stubsimplemanager_pool;
            unsigned old_size = stubsimplemanager_size;
            stubsimplemanager_size = stubsimplemanager_size * 2;
            stubsimplemanager_pool = new Simple*[stubsimplemanager_size];
            for (unsigned i = 0; i < old_size; ++i) {
                stubsimplemanager_pool[i] = old[i];
            }
            delete [] old;
        }
    }

    void StubStubManagerRegister(Simple* instance) {
        if (stubsimplemanager_pool == 0 || stubsimplemanager_next == stubsimplemanager_size) {
            StubStubManagerGrowPool();
        }
        stubsimplemanager_pool[stubsimplemanager_next] = instance;
        stubsimplemanager_next += 1;
    }

    void StubStubManagerUnRegister(Simple* instance) {
        for (unsigned i = 0; i < stubsimplemanager_size; ++i) {
            if (stubsimplemanager_pool[i] == instance) {
                stubsimplemanager_pool[i] = 0;
                break;
            }
        }
    }

";
    mixin TestFixture;

    m.renderRegisterFunc(hdr, impl);
    auto r = impl.render;
    assert(expect == r, r);
}

@name("Test rendering of register and unregister implementation")
unittest {
    auto expect = "    ::StubInternalSimple::StubStubManagerRegister(instance);
";
    mixin TestFixture;

    m.renderRegister(CppVariable("instance"), impl);
    auto r = impl.render;
    assert(expect == r, r);

    expect = "    ::StubInternalSimple::StubStubManagerUnRegister(instance);
";
    impl = new CppModule;
    m.renderUnRegister(CppVariable("instance"), impl);
    r = impl.render;
    assert(expect == r, r);
}

@name("Test rendering of class declaration")
unittest {
    auto expect = "class StubSimpleManager {
public:
    StubSimpleManager();
    ~StubSimpleManager();

    /// Get the first instance created.
    /// @return Pointer to instance or null if none is created.
    Simple* GetInstance();

    /// Get the Nth instance created.
    /// @return Pointer to instance or null if none was found.
    Simple* GetInstance(unsigned nth);
};

";
    mixin TestFixture;
    hdr.suppressThisIndent(1);

    m.renderClass(hdr, impl);
    auto r = hdr.render;
    assert(expect == r, r);
}

///TODO add check if pool is zero. Then force a crash.
@name("Test rendering of class implementation")
unittest {
    auto expect = "    StubSimpleManager::StubSimpleManager() {
    }

    StubSimpleManager::~StubSimpleManager() {
        for (unsigned i = 0; i < ::StubInternalSimple::stubsimplemanager_size; ++i) {
            if (::StubInternalSimple::stubsimplemanager_pool[i] != 0) {
                delete ::StubInternalSimple::stubsimplemanager_pool[i];
            }
        }
        delete [] ::StubInternalSimple::stubsimplemanager_pool;
        ::StubInternalSimple::stubsimplemanager_pool = 0;
        ::StubInternalSimple::stubsimplemanager_size = 0;
        ::StubInternalSimple::stubsimplemanager_next = 0;
    }

    Simple* StubSimpleManager::GetInstance() {
        if (::StubInternalSimple::stubsimplemanager_size > 0) {
            return ::StubInternalSimple::stubsimplemanager_pool[0];
        }
        return reinterpret_cast< Simple*>(0);
    }

    Simple* StubSimpleManager::GetInstance(unsigned nth) {
        if (::StubInternalSimple::stubsimplemanager_size > nth) {
            return ::StubInternalSimple::stubsimplemanager_pool[nth];
        }
        return reinterpret_cast< Simple*>(0);
    }

";
    mixin TestFixture;

    m.renderClass(hdr, impl);
    auto r = impl.render;
    assert(expect == r, r);
}
