/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// Representation of the structure of C/C++ code in D.
///
/// The guiding principle for this module is: "Correct by construction"
/// It is the reason why the c'tor are huge.
/// After the data is created it should be "correct".
/// As far as possible avoid runtime errors.
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
module cpptooling.data.representation;

import std.array : Appender;
import std.range : isInputRange;
import std.typecons : Typedef, Tuple, Flag;
import std.variant : Algebraic;
import logger = std.experimental.logger;

import cpptooling.analyzer.type : TypeKind, makeTypeKind, duplicate, toString;
import cpptooling.utility.range : arrayRange;
import cpptooling.utility.conv : str;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import unit_threaded : Name;
    import unit_threaded : shouldBeTrue, shouldEqual, shouldBeGreaterThan;

    enum dummyLoc = CxLocation("a.h", 123, 45);
    enum dummyLoc2 = CxLocation("a.h", 456, 12);
} else {
    struct Name {
        string name_;
    }
}

/// Name of a C++ namespace.
alias CppNs = Typedef!(string, string.init, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];
/// Nesting of C++ namespaces as a string.
alias CppNsNesting = Typedef!(string, string.init, "CppNsNesting");

alias CppVariable = Typedef!(string, string.init, "CppVariable");
alias TypeKindVariable = Tuple!(TypeKind, "type", CppVariable, "name");

// Types for classes
alias CppClassName = Typedef!(string, string.init, "CppClassName");

///TODO should be Optional type, either it has a nesting or it is "global".
/// Don't check the length and use that as an insidential "no nesting".
alias CppClassNesting = Typedef!(string, string.init, "CppNesting");

alias CppClassVirtual = Typedef!(VirtualType, VirtualType.No, "CppClassVirtual");
alias CppClassInherit = Tuple!(CppClassName, "name", CppClassNesting,
    "nesting", CppAccess, "access");

// Types for methods
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppConstMethod = Typedef!(bool, bool.init, "CppConstMethod");
alias CppVirtualMethod = Typedef!(VirtualType, VirtualType.No, "CppVirtualMethod");
alias CppAccess = Typedef!(AccessType, AccessType.Private, "CppAccess");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");

// Shared types between C and Cpp
alias VariadicType = Flag!"isVariadic";
alias CxParam = Algebraic!(TypeKindVariable, TypeKind, VariadicType);
alias CxReturnType = Typedef!(TypeKind, TypeKind.init, "CxReturnType");

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

/// Expects a toString function where it is mixed in.
/// base value for hash is 0 to force deterministic hashes. Use the pointer for
/// unique between objects.
private template mixinUniqueId() {
    //TODO add check to see that this do NOT already have id_.
    //TODO make id_ a Algebraic type or Nullable to force it to be set before used.

    private size_t id_;

    private void setUniqueId(string identifier) {
        static size_t makeUniqueId(string identifier) {
            import std.digest.crc;

            size_t value = 0;

            if (identifier is null)
                return value;
            ubyte[4] hash = crc32Of(identifier);
            return value ^ ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
        }

        this.id_ = makeUniqueId(identifier);
    }

    size_t id() const @property {
        return id_;
    }

    int opCmp(T : typeof(this))(auto ref const T rhs) const {
        return id() < rhs.id();
    }

    bool opEquals(T : typeof(this))(auto ref const T rhs) {
        return id() == rhs.id();
    }
}

/// User defined kind to differeniate structs of the same type.
private template mixinKind() {
    private int kind_;

    void setKind(int kind) {
        this.kind_ = kind;
    }

    @property const {
        auto kind() {
            return kind_;
        }
    }
}

///TODO change to a algebraic with two kinds, Location and None.
pure @safe nothrow struct CxLocation {
    string file;
    uint line;
    uint column;
    uint offset;

    auto toString() const {
        import std.format : format;

        return format("File:%s Line:%s Column:%s", file, line, column);
    }
}

/// The source location.
private template mixingSourceLocation() {
    private CxLocation loc_;

    private void setLocation(CxLocation loc) {
        this.loc_ = loc;
    }

    @property const {
        auto location() {
            return loc_;
        }
    }
}

/// Return: sorted and deduplicated array of the range.
///TODO can it be implemented more efficient?
auto dedup(T)(auto ref T r) @safe if (isInputRange!T) {
    import std.array : array;
    import std.algorithm : makeIndex, uniq, map;

    auto arr = r.array();
    auto index = new size_t[r.length];
    makeIndex(r, index);

    // dfmt off
    auto rval = index.uniq!((a,b) => arr[a] == arr[b])
        .map!(a => arr[a])
        .array();
    // dfmt on

    return rval;
}

/// Convert a namespace stack to a string separated by ::.
string toStringNs(CppNsStack ns) @safe {
    import std.algorithm : map;
    import std.array : join;

    return ns.map!(a => cast(string) a).join("::");
}

/// Convert a CxParam to a string.
string toInternal(CxParam p) @trusted {
    import std.variant : visit;

    // dfmt off
    return p.visit!(
        (TypeKindVariable tk) {return tk.type.toString(tk.name.str);},
        (TypeKind t) { return t.txt; },
        (VariadicType a) { return "..."; }
        );
    // dfmt on
}

/// Join a range of CxParams to a string separated by ", ".
string joinParams(T)(T r) @safe if (isInputRange!T) {
    import std.algorithm : joiner, map;
    import std.conv : text;
    import std.range : enumerate;

    static string getTypeName(T : const(Tx), Tx)(T p, ulong uid) @trusted {
        import std.variant : visit;

        // dfmt off
        auto x = (cast(Tx) p).visit!(
            (TypeKindVariable tk) {return tk.type.toString(tk.name.str);},
            (TypeKind t) { return t.toString("x" ~ text(uid)); },
            (VariadicType a) { return "..."; }
            );
        // dfmt on
        return x;
    }

    return r.enumerate.map!(a => getTypeName(a.value, a.index)).joiner(", ").text();
}

/// Join a range of CxParams by extracting the parameter names.
string joinParamNames(T)(T r) @safe if (isInputRange!T) {
    import std.algorithm : joiner, map, filter;
    import std.conv : text;
    import std.range : enumerate;

    static string getName(T : const(Tx), Tx)(T p, ulong uid) @trusted {
        import std.variant : visit;

        // dfmt off
        return (cast(Tx) p).visit!(
            (TypeKindVariable tk) {return tk.name.str;},
            (TypeKind t) { return "x" ~ text(uid); },
            (VariadicType a) { return ""; }
            );
        // dfmt on
    }

    // using cache to avoid getName is called twice.
    return r.enumerate.map!(a => getName(a.value, a.index)).filter!(a => a.length > 0).joiner(", ").text();
}

/// Make a variadic parameter.
CxParam makeCxParam() @trusted {
    return CxParam(VariadicType.yes);
}

/// CParam created by analyzing a TypeKindVariable.
/// A empty variable name means it is of the algebraic type TypeKind.
CxParam makeCxParam(TypeKindVariable tk) @trusted {
    if (tk.name.length == 0)
        return CxParam(tk.type);
    return CxParam(tk);
}

private static void assertVisit(T : const(Tx), Tx)(ref T p) @trusted {
    import std.variant : visit;

    // dfmt off
    (cast(Tx) p).visit!(
        (TypeKindVariable tk) { assert(tk.name.length > 0);
                                assert(tk.type.txt.length > 0);},
        (TypeKind t)          { assert(t.txt.length > 0); },
        (VariadicType a)      {});
    // dfmt on
}

pure @safe nothrow struct CxGlobalVariable {
    mixin mixinUniqueId;
    mixin mixingSourceLocation;

    @disable this();

    this(TypeKindVariable tk, CxLocation loc) {
        this.variable = tk;
        setLocation(loc);
        setUniqueId(variable.name.str);
    }

    this(TypeKind type, CppVariable name, CxLocation loc) {
        this(TypeKindVariable(type, name), loc);
    }

    string toString() const @safe {
        import std.array : Appender, appender;
        import std.format : formattedWrite;
        import std.ascii : newline;
        import cpptooling.analyzer.type : TypeKind;

        auto app = appender!string();
        final switch (variable.type.info.kind) with (TypeKind.Info) {
        case Kind.simple:
            formattedWrite(app, variable.type.info.fmt, variable.name.str);
            break;
        case Kind.array:
            formattedWrite(app, variable.type.info.fmt,
                variable.type.info.elementType, variable.name.str, variable.type.info.indexes);
            break;
        case Kind.funcPtr:
            formattedWrite(app, variable.type.info.fmt, variable.name.str);
            break;
        case Kind.null_:
            logger.error("Type of global variable is null. Identifier ", variable.name.str);
            break;
        }
        formattedWrite(app, "; // %s", location());

        return app.data;
    }

    @property const {
        auto type() {
            return variable.type;
        }

        auto name() {
            return variable.name;
        }

        auto typeName() {
            return variable;
        }
    }

private:
    TypeKindVariable variable;
}

struct CppMethodGeneric {
    template Parameters() {
        void put(const CxParam p) {
            params ~= p;
        }

        auto paramRange() const @nogc @safe pure nothrow {
            return arrayRange(params);
        }

        private CxParam[] params;
    }

    /** Common properties for C++ methods.
     *
     * Defines the needed variables.
     * Expecting them to be set in c'tors.
     */
    template Properties() {
        @property const {
            auto isConst() {
                return isConst_;
            }

            bool isVirtual() {
                return isVirtual_ != VirtualType.No;
            }

            auto virtualType() {
                return isVirtual_;
            }

            auto accessType() {
                return accessType_;
            }

            auto returnType() {
                return returnType_;
            }

            auto name() {
                return name_;
            }
        }

        private bool isConst_;
        private VirtualType isVirtual_;
        private CppAccess accessType_;
        private CppMethodName name_;
    }

    /// Helper for converting virtual type to string
    template StringHelperVirtual() {
        void helperVirtualPre(AppT)(AppT app) const @safe {
            switch (virtualType()) {
            case VirtualType.Yes:
            case VirtualType.Pure:
                app.put("virtual ");
                break;
            default:
            }
        }

        void helperVirtualPost(AppT)(AppT app) const @safe {
            switch (virtualType()) {
            case VirtualType.Pure:
                app.put(" = 0");
                break;
            default:
            }
        }
    }
}

/// Information about free functions.
pure @safe nothrow struct CFunction {
    import std.typecons : TypedefType;

    mixin mixinUniqueId;
    mixin mixingSourceLocation;

    @disable this();

    /// C function representation.
    this(const CFunctionName name, const CxParam[] params_,
        const CxReturnType return_type, const VariadicType is_variadic, const CxLocation loc) {
        this.name_ = name;
        this.returnType_ = duplicate(cast(const TypedefType!CxReturnType) return_type);
        this.isVariadic_ = is_variadic;

        //TODO how do you replace this with a range?
        foreach (p; params_) {
            this.params ~= p;
        }

        setLocation(loc);
        setUniqueId(internalToString);
    }

    /// Function with no parameters.
    this(const CFunctionName name, const CxReturnType return_type, const CxLocation loc) {
        this(name, CxParam[].init, return_type, VariadicType.no, loc);
    }

    /// Function with no parameters and returning void.
    this(const CFunctionName name, const CxLocation loc) {
        CxReturnType void_ = makeTypeKind("void", false, false, false);
        this(name, CxParam[].init, void_, VariadicType.no, loc);
    }

    /// A range over the parameters of the function.
    auto paramRange() const @nogc @safe pure nothrow {
        return arrayRange(params);
    }

    /// The return type of the function.
    auto returnType() const pure @safe @property {
        return returnType_;
    }

    /// Function name representation.
    auto name() @property const pure {
        return name_;
    }

    /// If the function is variadic, aka have a parameter with "...".
    bool isVariadic() {
        return VariadicType.yes == isVariadic_;
    }

    // Separating file location from the rest
    private string internalToString() const @safe {
        import std.array : Appender, appender;
        import std.format : formattedWrite;

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s);", returnType.txt, name.str, paramRange.joinParams);
        return rval.data;
    }

    string toString() const @safe {
        import std.array : Appender, appender;
        import std.format : formattedWrite;

        auto rval = appender!string();
        formattedWrite(rval, "%s // %s", internalToString(), location());

        return rval.data;
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.txt.length > 0);

        foreach (p; params) {
            assertVisit(p);
        }
    }

private:
    CFunctionName name_;

    CxParam[] params;
    CxReturnType returnType_;
    VariadicType isVariadic_;
}

pure @safe nothrow struct CppCtor {
    import std.typecons : TypedefType;

    //mixin mixinUniqueId;
    //mixin mixingSourceLocation;

    @disable this();

    this(const CppMethodName name, const CxParam[] params_, const CppAccess access) {
        this.name_ = name;
        this.accessType_ = access;

        //TODO how do you replace this with a range?
        foreach (p; params_) {
            this.params ~= p;
        }
    }

    mixin CppMethodGeneric.Parameters;

    string toString() const @safe {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;

        auto rval = appender!string();
        formattedWrite(rval, "%s(%s)", name_.str, paramRange.joinParams);

        return rval.data;
    }

    @property const {
        auto accessType() {
            return accessType_;
        }

        auto name() {
            return name_;
        }
    }

    invariant() {
        assert(name_.length > 0);

        foreach (p; params) {
            assertVisit(p);
        }
    }

private:
    CppAccess accessType_;

    CppMethodName name_;
}

pure @safe nothrow struct CppDtor {
    import std.typecons : TypedefType;

    //mixin mixinUniqueId;
    //mixin mixingSourceLocation;

    @disable this();

    this(const CppMethodName name, const CppAccess access, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.accessType_ = access;
        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;
    }

    mixin CppMethodGeneric.StringHelperVirtual;

    string toString() const @safe {
        import std.array : appender;

        auto rval = appender!string();
        helperVirtualPre(rval);

        rval.put(name_.str);
        rval.put("()");

        return rval.data;
    }

    @property const {
        bool isVirtual() {
            return isVirtual_ != VirtualType.No;
        }

        auto virtualType() {
            return isVirtual_;
        }

        auto accessType() {
            return accessType_;
        }

        auto name() {
            return name_;
        }
    }

    invariant() {
        assert(name_.length > 0);
        assert(isVirtual_ != VirtualType.Pure);
    }

private:
    VirtualType isVirtual_;
    CppAccess accessType_;

    CppMethodName name_;
}

pure @safe nothrow struct CppMethod {
    import std.typecons : TypedefType;

    //mixin mixinUniqueId;
    //mixin mixingSourceLocation;

    @disable this();

    this(const CppMethodName name, const CxParam[] params_,
        const CxReturnType return_type, const CppAccess access,
        const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.returnType_ = duplicate(cast(const TypedefType!CxReturnType) return_type);
        this.accessType_ = access;
        this.isConst_ = cast(TypedefType!CppConstMethod) const_;
        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;

        //TODO how do you replace this with a range?
        foreach (p; params_) {
            this.params ~= p;
        }
    }

    /// Function with no parameters.
    this(const CppMethodName name, const CxReturnType return_type,
        const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this(name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(const CppMethodName name, const CppAccess access,
        const CppConstMethod const_ = false, const CppVirtualMethod virtual = VirtualType.No) {
        CxReturnType void_ = makeTypeKind("void", false, false, false);
        this(name, CxParam[].init, void_, access, const_, virtual);
    }

    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.Properties;

    string toString() const @safe {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;

        auto rval = appender!string();
        helperVirtualPre(rval);
        formattedWrite(rval, "%s %s(%s)", returnType_.txt, name_.str, paramRange.joinParams);

        if (isConst) {
            rval.put(" const");
        }

        helperVirtualPost(rval);

        return rval.data;
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.txt.length > 0);

        foreach (p; params) {
            assertVisit(p);
        }
    }

private:
    CxReturnType returnType_;
}

pure @safe nothrow struct CppMethodOp {
    import std.typecons : TypedefType;

    @disable this();

    this(const CppMethodName name, const CxParam[] params_,
        const CxReturnType return_type, const CppAccess access,
        const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.returnType_ = duplicate(cast(const TypedefType!CxReturnType) return_type);
        this.accessType_ = access;
        this.isConst_ = cast(TypedefType!CppConstMethod) const_;
        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;

        //TODO how do you replace this with a range?
        foreach (p; params_) {
            this.params ~= p;
        }
    }

    /// Operator with no parameters.
    this(const CppMethodName name, const CxReturnType return_type,
        const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this(name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Operator with no parameters and returning void.
    this(const CppMethodName name, const CppAccess access,
        const CppConstMethod const_ = false, const CppVirtualMethod virtual = VirtualType.No) {
        CxReturnType void_ = makeTypeKind("void", false, false, false);
        this(name, CxParam[].init, void_, access, const_, virtual);
    }

    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.Properties;

    string toString() const @safe {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;

        auto rval = appender!string();
        helperVirtualPre(rval);
        formattedWrite(rval, "%s %s(%s)", returnType_.txt, name_.str, paramRange.joinParams);

        if (isConst) {
            rval.put(" const");
        }

        helperVirtualPost(rval);

        // distinguish an operator from a normal method
        rval.put(" /* operator */");

        return rval.data;
    }

    @property const {
        /// The operator type, aka in C++ the part after "operator"
        auto op()
        in {
            assert(name_.length > 8);
        }
        body {
            return CppMethodName((cast(string) name_)[8 .. $]);
        }
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.txt.length > 0);

        foreach (p; params) {
            assertVisit(p);
        }
    }

private:
    CxReturnType returnType_;
}

pure @safe nothrow struct CppClass {
    import std.variant : Algebraic, visit;
    import std.typecons : TypedefType;

    alias CppFunc = Algebraic!(CppMethod, CppMethodOp, CppCtor, CppDtor);

    mixin mixinUniqueId;
    mixin mixinKind;
    mixin mixingSourceLocation;

    @disable this();

    this(const CppClassName name, const CxLocation loc, const CppClassInherit[] inherits) {
        this.name_ = name;
        this.inherits_ = inherits.dup;
        setLocation(loc);

        ///TODO consider update so the identifier also depend on the namespace.
        setUniqueId(this.name_.str);
    }

    this(const CppClassName name, const CxLocation loc) {
        this(name, loc, CppClassInherit[].init);
    }

    this(const CppClassName name) {
        this(name, CxLocation("noloc", 0, 0), CppClassInherit[].init);
    }

    void put(T)(T func) @trusted if (is(T == CppMethod) || is(T == CppCtor)
            || is(T == CppDtor) || is(T == CppMethodOp)) {
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

        this.st = StateType.Dirty;
        updateVirt(this);
    }

    void put(T)(T class_, AccessType accessType) @trusted if (is(T == CppClass)) {
        final switch (accessType) {
        case AccessType.Public:
            classes_pub ~= class_;
            break;
        case AccessType.Protected:
            classes_prot ~= class_;
            break;
        case AccessType.Private:
            classes_priv ~= class_;
            break;
        }
    }

    /// Add a comment string to the class.
    void put(string comment) {
        cmnt ~= comment;
    }

    auto inheritRange() const @nogc @safe pure nothrow {
        return arrayRange(inherits_);
    }

    auto methodRange() @nogc @safe pure nothrow {
        import std.range : chain;

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

    auto classRange() @nogc @safe pure nothrow {
        import std.range : chain;

        return chain(classes_pub, classes_prot, classes_priv);
    }

    auto classPublicRange() @nogc @safe pure nothrow {
        return arrayRange(classes_pub);
    }

    auto classProtectedRange() @nogc @safe pure nothrow {
        return arrayRange(classes_prot);
    }

    auto classPrivateRange() @nogc @safe pure nothrow {
        return arrayRange(classes_priv);
    }

    auto commentRange() const @nogc @safe pure nothrow {
        return arrayRange(cmnt);
    }

    ///TODO make the function const.
    string toString() const @safe {
        import std.array : Appender, appender;
        import std.conv : to;
        import std.algorithm : each;
        import std.ascii : newline;
        import std.format : formattedWrite;

        static string funcToString(CppFunc func) @trusted {
            //dfmt off
            return func.visit!((CppMethod a) => a.toString,
                               (CppMethodOp a) => a.toString,
                               (CppCtor a) => a.toString,
                               (CppDtor a) => a.toString);
            //dfmt on
        }

        static void appPubRange(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            if (th.methods_pub.length > 0 || th.classes_pub.length > 0) {
                formattedWrite(app, "public:%s", newline);
                (cast(Tx) th).methodPublicRange.each!(a => formattedWrite(app,
                    "  %s;%s", funcToString(a), newline));
                (cast(Tx) th).classPublicRange.each!(a => formattedWrite(app,
                    "%s%s", a.toString(), newline));
            }
        }

        static void appProtRange(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            if (th.methods_prot.length > 0 || th.classes_prot.length > 0) {
                formattedWrite(app, "protected:%s", newline);
                (cast(Tx) th).methodProtectedRange.each!(a => formattedWrite(app,
                    "  %s;%s", funcToString(a), newline));
                (cast(Tx) th).classProtectedRange.each!(a => formattedWrite(app,
                    "%s%s", a.toString(), newline));
            }
        }

        static void appPrivRange(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            if (th.methods_priv.length > 0 || th.classes_priv.length > 0) {
                formattedWrite(app, "private:%s", newline);
                (cast(Tx) th).methodPrivateRange.each!(a => formattedWrite(app,
                    "  %s;%s", funcToString(a), newline));
                (cast(Tx) th).classPrivateRange.each!(a => formattedWrite(app,
                    "%s%s", a.toString(), newline));
            }
        }

        static string inheritRangeToString(T)(T range) @trusted {
            import std.range : enumerate;
            import std.string : toLower;

            auto app = appender!string();
            // dfmt off
            range.enumerate(0)
                .each!(a => formattedWrite(app, "%s%s %s%s",
                       a.index == 0 ? " : " : ", ",
                       to!string(cast (TypedefType!(typeof(a.value.access))) a.value.access).toLower,
                       a.value.nesting.str,
                       a.value.name.str));
            // dfmt on

            return app.data;
        }

        auto app = appender!string();

        commentRange().each!(a => formattedWrite(app, "// %s%s", a, newline));

        formattedWrite(app, "class %s%s { // isVirtual %s %s%s", name_.str,
            inheritRangeToString(inheritRange()), to!string(virtualType()),
            location.toString, newline);
        appPubRange(this, app);
        appProtRange(this, app);
        appPrivRange(this, app);
        formattedWrite(app, "}; //Class:%s", name_.str);

        return app.data;
    }

    invariant() {
        assert(name_.length > 0);
        foreach (i; inherits_) {
            assert(i.name.length > 0);
        }
    }

    @property const {
        bool isVirtual() {
            return isVirtual_ != VirtualType.No;
        }

        auto virtualType() {
            return isVirtual_;
        }

        auto name() {
            return name_;
        }

        auto inherits() {
            return inherits_;
        }
    }

private:
    static void updateVirt(T : const(Tx), Tx)(ref T th) @trusted {
        if (StateType.Dirty == th.st) {
            (cast(Tx) th).isVirtual_ = analyzeVirtuality(cast(Tx) th);
            (cast(Tx) th).st = StateType.Clean;
        }
    }

    // Dirty if the virtuality has to be recalculated.
    enum StateType {
        Dirty,
        Clean
    }

    //TODO remove state etc in the future if the current strategy works
    //regarding only reanalyze on put.
    StateType st;

    CppClassName name_;
    CppClassInherit[] inherits_;

    VirtualType isVirtual_ = VirtualType.Pure;

    CppFunc[] methods_pub;
    CppFunc[] methods_prot;
    CppFunc[] methods_priv;

    CppClass[] classes_pub;
    CppClass[] classes_prot;
    CppClass[] classes_priv;

    string[] cmnt;
}

// Clang have no function that says if a class is virtual/pure virtual.
// So have to post process.
private VirtualType analyzeVirtuality(CppClass th) @safe {
    import std.conv : to;

    struct Rval {
        enum Type {
            Normal,
            Ctor,
            Dtor
        }

        VirtualType value;
        Type t;
    }

    static auto getVirt(CppClass.CppFunc func) @trusted {
        import std.variant : visit;

        //dfmt off
        return func.visit!((CppMethod a) => Rval(a.virtualType(), Rval.Type.Normal),
                           (CppMethodOp a) => Rval(a.virtualType(), Rval.Type.Normal),
                           (CppCtor a) => Rval(VirtualType.No, Rval.Type.Ctor),
                           (CppDtor a) => Rval(a.virtualType(), Rval.Type.Dtor));
        //dfmt on
    }

    auto v = VirtualType.Pure;
    //TODO optimize the ranges so we don't traverse unnecessary

    // initialization with a value that affects virtualization classification
    // ctor and dtor do not.
    foreach (m; th.methodRange) {
        auto mVirt = getVirt(m);

        if (mVirt.t == Rval.Type.Normal) {
            v = mVirt.value;
            break;
        }
    }
    // initialized with a value from a method.
    foreach (m; th.methodRange) {
        auto mVirt = getVirt(m);

        final switch (mVirt.value) {
        case VirtualType.Pure:
            break;
        case VirtualType.Yes:
            if (mVirt.t == Rval.Type.Normal) {
                v = VirtualType.Yes;
            }
            break;
        case VirtualType.No:
            // a non-virtual destructor lowers purity
            if (v == VirtualType.Pure && mVirt.t == Rval.Type.Dtor) {
                v = VirtualType.No;
            }
            break;
        }

        debug {
            logger.trace(cast(string) th.name, ":", m.type, ":",
                to!string(mVirt), ":", to!string(v));
        }
    }

    debug {
        logger.trace(cast(string) th.name, ":sum:", to!string(v));
    }

    return v;
}

pure @safe nothrow struct CppNamespace {
    @disable this();

    //mixin mixinUniqueId;
    mixin mixinKind;
    //mixin mixingSourceLocation;

    static auto makeAnonymous() {
        return CppNamespace(CppNsStack.init);
    }

    /// A namespace without any nesting.
    static auto make(CppNs name) {
        return CppNamespace([name]);
    }

    this(const CppNsStack stack) {
        if (stack.length > 0) {
            this.name_ = stack[$ - 1];
        }
        this.isAnonymous_ = stack.length == 0;
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

    void put(CxGlobalVariable g) {
        globals ~= g;
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

    auto globalRange() @nogc @safe pure nothrow {
        return arrayRange(globals);
    }

    string toString() const @safe {
        import std.array : Appender, appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : retro;
        import std.ascii : newline;

        static void appRanges(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            (cast(Tx) th).globalRange.each!(a => formattedWrite(app, "%s%s",
                a.toString(), newline));
            (cast(Tx) th).funcRange.each!(a => formattedWrite(app, "%s%s", a.toString(),
                newline));
            (cast(Tx) th).classRange.each!(a => formattedWrite(app, "%s%s", a.toString(),
                newline));
            (cast(Tx) th).namespaceRange.each!(a => formattedWrite(app, "%s%s",
                a.toString(), newline));
        }

        static void nsToStrings(T : const(Tx), Tx)(ref T th, out string ns_name, out string ns_concat) @trusted {
            auto ns_app = appender!string();
            ns_name = "";
            ns_concat = "";

            auto ns_r = (cast(Tx) th).nsNestingRange().retro;
            if (!ns_r.empty) {
                ns_name = ns_r.back.str;
                ns_app.put(ns_r.front.str);
                ns_r.popFront;
                ns_r.each!(a => formattedWrite(ns_app, "::%s", a.str));
                ns_concat = ns_app.data;
            }
        }

        string ns_name;
        string ns_concat;
        nsToStrings(this, ns_name, ns_concat);

        auto app = appender!string();
        formattedWrite(app, "namespace %s { //%s%s", ns_name, ns_concat, newline);
        appRanges(this, app);
        formattedWrite(app, "} //NS:%s", ns_name);

        return app.data;
    }

    @property const {
        auto isAnonymous() {
            return isAnonymous_;
        }

        auto name() {
            return name_;
        }

    }

private:
    bool isAnonymous_;
    CppNs name_;

    CppNsStack stack;
    CppClass[] classes;
    CFunction[] funcs;
    CppNamespace[] namespaces;
    CxGlobalVariable[] globals;
}

pure @safe nothrow struct CppRoot {
    mixin mixingSourceLocation;

    this(in CxLocation loc) {
        setLocation(loc);
    }

    void put(CFunction f) {
        funcs ~= f;
    }

    void put(CppClass s) {
        classes ~= s;
    }

    void put(CppNamespace ns) {
        this.ns ~= ns;
    }

    void put(CxGlobalVariable g) {
        globals ~= g;
    }

    string toString() const @safe {
        import std.array : Appender, appender;
        import std.format : formattedWrite;
        import std.ascii : newline;

        static void appRanges(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            import std.algorithm : each;
            import std.ascii : newline;
            import std.format : formattedWrite;

            if (th.globals.length > 0) {
                (cast(Tx) th).globalRange.each!(a => formattedWrite(app, "%s%s",
                    a.toString(), newline));
                app.put(newline);
            }

            if (th.funcs.length > 0) {
                (cast(Tx) th).funcRange.each!(a => formattedWrite(app, "%s%s", a.toString,
                    newline));
                app.put(newline);
            }

            if (th.classes.length > 0) {
                (cast(Tx) th).classRange.each!(a => formattedWrite(app, "%s%s", a.toString,
                    newline));
                app.put(newline);
            }

            (cast(Tx) th).namespaceRange.each!(a => formattedWrite(app, "%s%s", a.toString,
                newline));
        }

        auto app = appender!string();
        formattedWrite(app, "// %s%s", location().toString, newline);
        appRanges(this, app);

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

    auto globalRange() @nogc @safe pure nothrow {
        return arrayRange(globals);
    }

private:
    CppNamespace[] ns;
    CppClass[] classes;
    CFunction[] funcs;
    CxGlobalVariable[] globals;
}

/// Find where in the structure a class with the uniqe id reside.
@safe CppNsStack whereIsClass(CppRoot root, const size_t id) {
    CppNsStack ns;

    foreach (c; root.classRange()) {
        if (c.id() == id) {
            return ns;
        }
    }

    return ns;
}

@Name("Test of c-function")
unittest {
    { // simple version, no return or parameters.
        auto f = CFunction(CFunctionName("nothing"), dummyLoc);
        shouldEqual(f.returnType.txt, "void");
        shouldEqual(f.toString, "void nothing(); // File:a.h Line:123 Column:45");
    }

    { // a return type.
        auto rtk = makeTypeKind("int", false, false, false);
        auto f = CFunction(CFunctionName("nothing"), CxReturnType(rtk), dummyLoc);
        shouldEqual(f.toString, "int nothing(); // File:a.h Line:123 Column:45");
    }

    { // return type and parameters.
        auto p0 = makeCxParam(TypeKindVariable(makeTypeKind("int", false,
            false, false), CppVariable("x")));
        auto p1 = makeCxParam(TypeKindVariable(makeTypeKind("char", false,
            false, false), CppVariable("y")));
        auto rtk = makeTypeKind("int", false, false, false);
        auto f = CFunction(CFunctionName("nothing"), [p0, p1],
            CxReturnType(rtk), VariadicType.no, dummyLoc);
        shouldEqual(f.toString, "int nothing(int x, char y); // File:a.h Line:123 Column:45");
    }
}

@Name("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    shouldEqual(m.isConst, false);
    shouldEqual(m.isVirtual, VirtualType.No);
    shouldEqual(m.name, "voider");
    shouldEqual(m.params.length, 0);
    shouldEqual(m.returnType.txt, "void");
    shouldEqual(m.accessType, AccessType.Public);
}

@Name("Test creating a CppMethod with multiple parameters")
unittest {
    auto tk = makeTypeKind("char*", false, false, true);
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto m = CppMethod(CppMethodName("none"), [p, p], CxReturnType(tk),
        CppAccess(AccessType.Public), CppConstMethod(true), CppVirtualMethod(VirtualType.Yes));

    shouldEqual(m.toString, "virtual char* none(char* x, char* x) const");
}

@Name("should represent the operator as a string")
unittest {
    auto m = CppMethodOp(CppMethodName("operator="), CppAccess(AccessType.Public));

    shouldEqual(m.toString, "void operator=() /* operator */");
}

@Name("should separate the operator keyword from the actual operator")
unittest {
    auto m = CppMethodOp(CppMethodName("operator="), CppAccess(AccessType.Public));

    shouldEqual(m.op, "=");
}

@Name("should represent a class with one public method")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    shouldEqual(c.methods_pub.length, 1);
    shouldEqualPretty(c.toString, "class Foo { // isVirtual No File:noloc Line:0 Column:0
public:
  void voider();
}; //Class:Foo");
}

@Name("should represent a class with one public oeprator overload")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto op = CppMethodOp(CppMethodName("operator="), CppAccess(AccessType.Public));
    c.put(op);

    shouldEqualPretty(c.toString, "class Foo { // isVirtual No File:noloc Line:0 Column:0
public:
  void operator=() /* operator */;
}; //Class:Foo");
}

@Name("Create an anonymous namespace struct")
unittest {
    auto n = CppNamespace(CppNsStack.init);
    shouldEqual(n.name.length, 0);
    shouldEqual(n.isAnonymous, true);
}

@Name("Create a namespace struct two deep")
unittest {
    auto stack = [CppNs("foo"), CppNs("bar")];
    auto n = CppNamespace(stack);
    shouldEqual(n.name, "bar");
    shouldEqual(n.isAnonymous, false);
}

@Name("Test of iterating over parameters in a class")
unittest {
    import std.array : appender;

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);

    auto app = appender!string();
    foreach (d; c.methodRange) {
        app.put(d.toString());
    }

    shouldEqual(app.data, "void voider()");
}

@Name("Test of toString for a free function")
unittest {
    auto ptk = makeTypeKind("char*", false, false, true);
    auto rtk = makeTypeKind("int", false, false, false);
    auto f = CFunction(CFunctionName("nothing"),
        [makeCxParam(TypeKindVariable(ptk, CppVariable("x"))),
        makeCxParam(TypeKindVariable(ptk, CppVariable("y")))],
        CxReturnType(rtk), VariadicType.no, dummyLoc);

    shouldEqualPretty(f.toString, "int nothing(char* x, char* y); // File:a.h Line:123 Column:45");
}

@Name("Test of Ctor's")
unittest {
    auto tk = makeTypeKind("char*", false, false, true);
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto ctor = CppCtor(CppMethodName("ctor"), [p, p], CppAccess(AccessType.Public));

    shouldEqual(ctor.toString, "ctor(char* x, char* x)");
}

@Name("Test of Dtor's")
unittest {
    auto dtor = CppDtor(CppMethodName("~dtor"), CppAccess(AccessType.Public),
        CppVirtualMethod(VirtualType.Yes));

    shouldEqual(dtor.toString, "virtual ~dtor()");
}

@Name("Test of toString for CppClass")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public)));

    {
        auto m = CppCtor(CppMethodName("Foo"), CxParam[].init, CppAccess(AccessType.Public));
        c.put(m);
    }

    {
        auto tk = makeTypeKind("int", false, false, false);
        auto m = CppMethod(CppMethodName("fun"), CxReturnType(tk),
            CppAccess(AccessType.Protected), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("gun"),
            CxReturnType(makeTypeKind("char*", false, false, true)),
            CppAccess(AccessType.Private), CppConstMethod(false),
            CppVirtualMethod(VirtualType.No));
        m.put(CxParam(TypeKindVariable(makeTypeKind("int", false, false, false), CppVariable("x"))));
        m.put(CxParam(TypeKindVariable(makeTypeKind("int", false, false, false), CppVariable("y"))));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeTypeKind("int", false, false, true)),
            CppAccess(AccessType.Public), CppConstMethod(true), CppVirtualMethod(VirtualType.No));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // isVirtual No File:noloc Line:0 Column:0
public:
  void voider();
  Foo();
  int wun() const;
protected:
  virtual int fun() = 0;
private:
  char* gun(int x, int y);
}; //Class:Foo");
}

@Name("should contain the inherited classes")
unittest {
    CppClassInherit[] inherit;
    inherit ~= CppClassInherit(CppClassName("pub"), CppClassNesting(""),
        CppAccess(AccessType.Public));
    inherit ~= CppClassInherit(CppClassName("prot"), CppClassNesting(""),
        CppAccess(AccessType.Protected));
    inherit ~= CppClassInherit(CppClassName("priv"), CppClassNesting(""),
        CppAccess(AccessType.Private));

    auto c = CppClass(CppClassName("Foo"), dummyLoc, inherit);

    shouldEqualPretty(
        c.toString,
        "class Foo : public pub, protected prot, private priv { // isVirtual Pure File:a.h Line:123 Column:45
}; //Class:Foo");
}

@Name("should contain nested classes")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    c.put(CppClass(CppClassName("Pub")), AccessType.Public);
    c.put(CppClass(CppClassName("Prot")), AccessType.Protected);
    c.put(CppClass(CppClassName("Priv")), AccessType.Private);

    shouldEqualPretty(c.toString, "class Foo { // isVirtual Pure File:noloc Line:0 Column:0
public:
class Pub { // isVirtual Pure File:noloc Line:0 Column:0
}; //Class:Pub
protected:
class Prot { // isVirtual Pure File:noloc Line:0 Column:0
}; //Class:Prot
private:
class Priv { // isVirtual Pure File:noloc Line:0 Column:0
}; //Class:Priv
}; //Class:Foo");
}

@Name("should be a virtual class")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppCtor(CppMethodName("Foo"), CxParam[].init, CppAccess(AccessType.Public));
        c.put(m);
    }
    {
        auto m = CppDtor(CppMethodName("~Foo"), CppAccess(AccessType.Public),
            CppVirtualMethod(VirtualType.Yes));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeTypeKind("int", false, false, true)),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Yes));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // isVirtual Yes File:noloc Line:0 Column:0
public:
  Foo();
  virtual ~Foo();
  virtual int wun();
}; //Class:Foo");
}

@Name("should be a pure virtual class")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppCtor(CppMethodName("Foo"), CxParam[].init, CppAccess(AccessType.Public));
        c.put(m);
    }
    {
        auto m = CppDtor(CppMethodName("~Foo"), CppAccess(AccessType.Public),
            CppVirtualMethod(VirtualType.Yes));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeTypeKind("int", false, false, true)),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // isVirtual Pure File:noloc Line:0 Column:0
public:
  Foo();
  virtual ~Foo();
  virtual int wun() = 0;
}; //Class:Foo");
}

@Name("Test of toString for CppNamespace")
unittest {
    auto ns = CppNamespace.make(CppNs("simple"));

    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public)));
    ns.put(c);

    shouldEqualPretty(ns.toString, "namespace simple { //simple
class Foo { // isVirtual No File:noloc Line:0 Column:0
public:
  void voider();
}; //Class:Foo
} //NS:simple");
}

@Name("Should show nesting of namespaces as valid C++ code")
unittest {
    auto stack = [CppNs("foo"), CppNs("bar")];
    auto n = CppNamespace(stack);
    shouldEqualPretty(n.toString, "namespace bar { //foo::bar
} //NS:bar");
}

@Name("Test of toString for CppRoot")
unittest {
    CppRoot root;

    { // free function
        auto f = CFunction(CFunctionName("nothing"), dummyLoc);
        root.put(f);
    }

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    root.put(c);

    root.put(CppNamespace.make(CppNs("simple")));

    shouldEqualPretty(root.toString, "// File: Line:0 Column:0
void nothing(); // File:a.h Line:123 Column:45

class Foo { // isVirtual No File:noloc Line:0 Column:0
public:
  void voider();
}; //Class:Foo

namespace simple { //simple
} //NS:simple
");
}

@Name("CppNamespace.toString should return nested namespace")
unittest {
    auto stack = [CppNs("Depth1"), CppNs("Depth2"), CppNs("Depth3")];
    auto depth1 = CppNamespace(stack[0 .. 1]);
    auto depth2 = CppNamespace(stack[0 .. 2]);
    auto depth3 = CppNamespace(stack[0 .. $]);

    depth2.put(depth3);
    depth1.put(depth2);

    shouldEqualPretty(depth1.toString, "namespace Depth1 { //Depth1
namespace Depth2 { //Depth1::Depth2
namespace Depth3 { //Depth1::Depth2::Depth3
} //NS:Depth3
} //NS:Depth2
} //NS:Depth1");
}

@Name("Create anonymous namespace")
unittest {
    auto n = CppNamespace.makeAnonymous();

    shouldEqualPretty(n.toString, "namespace  { //
} //NS:");
}

@Name("Add a C-func to a namespace")
unittest {
    auto n = CppNamespace.makeAnonymous();
    auto f = CFunction(CFunctionName("nothing"), dummyLoc);
    n.put(f);

    shouldEqualPretty(n.toString, "namespace  { //
void nothing(); // File:a.h Line:123 Column:45
} //NS:");
}

@Name("should be a hash value based on string representation")
unittest {
    struct A {
        mixin mixinUniqueId;
        this(bool fun) {
            setUniqueId("foo");
        }
    }

    auto a = A(true);
    auto b = A(true);

    shouldBeGreaterThan(a.id(), 0);
    shouldEqual(a.id(), b.id());
}

@Name("should be a global definition")
unittest {
    auto v0 = CxGlobalVariable(TypeKindVariable(makeTypeKind("int", false,
        false, false), CppVariable("x")), dummyLoc);
    auto v1 = CxGlobalVariable(makeTypeKind("int", false, false, false), CppVariable("y"),
        dummyLoc);

    shouldEqualPretty(v0.toString, "int x; // File:a.h Line:123 Column:45");
    shouldEqualPretty(v1.toString, "int y; // File:a.h Line:123 Column:45");
}

@Name("globals in root")
unittest {
    auto v = CxGlobalVariable(TypeKindVariable(makeTypeKind("int", false,
        false, false), CppVariable("x")), dummyLoc);
    auto n = CppNamespace.makeAnonymous();
    auto r = CppRoot();
    n.put(v);
    r.put(v);
    r.put(n);

    shouldEqualPretty(r.toString, "// File: Line:0 Column:0
int x; // File:a.h Line:123 Column:45

namespace  { //
int x; // File:a.h Line:123 Column:45
} //NS:
");
}

@Name("Root with location")
unittest {
    auto r = CppRoot(dummyLoc);

    shouldEqualPretty(r.toString, "// File:a.h Line:123 Column:45
");
}

@Name("should be possible to sort the data structures")
unittest {
    auto v0 = CxGlobalVariable(TypeKindVariable(makeTypeKind("int", false,
        false, false), CppVariable("x")), dummyLoc);
    auto v1 = CxGlobalVariable(TypeKindVariable(makeTypeKind("int", false,
        false, false), CppVariable("x")), dummyLoc2);
    auto r = CppRoot();
    r.put(v0);
    r.put(v1);
    r.put(v0);

    auto s = r.globalRange().dedup();
    shouldEqual(s.length, 1);
}
