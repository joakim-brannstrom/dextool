// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Representation of the structure of C/C++ code in D.

The guiding principle for this module is: "Correct by construction".
 * After the data is created it should be "correct".
 * As far as possible avoid runtime errors.
Therefor the default c'tor is disabled.

Design rules for Structural representation.
 * default c'tor disabled.
 * attributes "pure @safe nothrow" for the struct.
 * All c'tor parameters shall be const.
 * After c'tor "const:" shall be used.
 * Ranges for arrays shall use the ArrayRange struct.
 * Add mixin for Id and Location when the need arise.
 * const: (The ':' is not a typo) can affect var members thus all member
   shall be defined after imports.
*/
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
    Pure,
    Unknown
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
private template mixinSourceLocation() {
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
    return r.enumerate.map!(a => getName(a.value, a.index)).filter!(a => a.length > 0)
        .joiner(", ").text();
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
    private TypeKindVariable variable;

    mixin mixinUniqueId;
    mixin mixinSourceLocation;

    @disable this();

    this(TypeKindVariable tk, CxLocation loc) {
        this.variable = tk;
        setLocation(loc);
        setUniqueId(variable.name.str);
    }

    this(TypeKind type, CppVariable name, CxLocation loc) {
        this(TypeKindVariable(type, name), loc);
    }

const:

    string toString() {
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
            logger.error("Type of global variable is null. Identifier ",
                    variable.name.str);
            break;
        }
        formattedWrite(app, "; // %s", location());

        return app.data;
    }

    @property {
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
}

struct CppMethodGeneric {
    template Parameters() {
        void put(const CxParam p) {
            params_ ~= p;
        }

        auto paramRange() const @nogc @safe pure nothrow {
            return arrayRange(params_);
        }

        private CxParam[] params_;
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
        static string helperVirtualPre(VirtualType pre) @safe pure nothrow @nogc {
            switch (pre) {
            case VirtualType.Yes:
            case VirtualType.Pure:
                return "virtual ";
            default:
                return "";
            }
        }

        static string helperVirtualPost(VirtualType post) @safe pure nothrow @nogc {
            switch (post) {
            case VirtualType.Pure:
                return " = 0";
            default:
                return "";
            }
        }

        static string helperConst(bool is_const) @safe pure nothrow @nogc {
            final switch (is_const) {
            case true:
                return " const";
            case false:
                return "";
            }
        }
    }
}

/// Information about free functions.
/// TODO: rename to CxFreeFunction
pure @safe nothrow struct CFunction {
    import std.typecons : TypedefType;

    private {
        CFunctionName name_;
        CxParam[] params;
        CxReturnType returnType_;
        VariadicType isVariadic_;
    }

    mixin mixinUniqueId;
    mixin mixinSourceLocation;

    @disable this();

    /// C function representation.
    this(const CFunctionName name, const CxParam[] params_, const CxReturnType return_type,
            const VariadicType is_variadic, const CxLocation loc) {
        this.name_ = name;
        this.returnType_ = return_type;
        this.isVariadic_ = is_variadic;

        this.params = params_.dup;

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

const:

    /// A range over the parameters of the function.
    auto paramRange() @nogc @safe pure nothrow {
        return arrayRange(params);
    }

    /// The return type of the function.
    auto returnType() @property {
        return returnType_;
    }

    /// Function name representation.
    auto name() @property {
        return name_;
    }

    /// If the function is variadic, aka have a parameter with "...".
    bool isVariadic() {
        return VariadicType.yes == isVariadic_;
    }

    // Separating file location from the rest
    private string internalToString() {
        import std.array : Appender, appender;
        import std.format : formattedWrite;

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s);", returnType.txt, name.str, paramRange.joinParams);
        return rval.data;
    }

    string toString() {
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
}

/** Represent a C++ constructor.
 *
 * The construction of CppCtor is simplified in the example.
 * Example:
 * ----
 * class A {
 * public:
 *    A();      // CppCtor("A", null, Public);
 *    A(int x); // CppCtor("A", ["int x"], Public);
 * };
 * ----
 */
pure @safe nothrow struct CppCtor {
    private {
        CppAccess accessType_;
        CppMethodName name_;
    }

    @disable this();

    this(const CppMethodName name, const CxParam[] params, const CppAccess access) {
        this.name_ = name;
        this.accessType_ = access;
        this.params_ = params.dup;
    }

    mixin CppMethodGeneric.Parameters;

const:

    string toString() {
        import std.format : format;

        return format("%s(%s)", name_.str, paramRange.joinParams);
    }

    @property {
        auto accessType() {
            return accessType_;
        }

        auto name() {
            return name_;
        }
    }

    invariant() {
        assert(name_.length > 0);

        foreach (p; params_) {
            assertVisit(p);
        }
    }
}

pure @safe nothrow struct CppDtor {
    private {
        VirtualType isVirtual_;
        CppAccess accessType_;
        CppMethodName name_;
    }

    @disable this();

    this(const CppMethodName name, const CppAccess access, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.accessType_ = access;

        import std.typecons : TypedefType;

        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;
    }

    mixin CppMethodGeneric.StringHelperVirtual;

const:

    string toString() {
        import std.algorithm : joiner;
        import std.range : only;
        import std.conv : text;

        // dfmt off
        return
            only(
                 helperVirtualPre(virtualType),
                 name_.str,
                 "()"
                )
            .joiner()
            .text;
        // dfmt on
    }

    @property {
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
}

pure @safe nothrow struct CppMethod {
    private CxReturnType returnType_;

    @disable this();

    this(const CppMethodName name, const CxParam[] params, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.returnType_ = return_type;
        this.accessType_ = access;
        this.params_ = params.dup;

        import std.typecons : TypedefType;

        this.isConst_ = cast(TypedefType!CppConstMethod) const_;
        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;
    }

    /// Function with no parameters.
    this(const CppMethodName name, const CxReturnType return_type, const CppAccess access,
            const CppConstMethod const_, const CppVirtualMethod virtual) {
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

const:

    string toString() {
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only;

        // dfmt off
        return
            only(
                 helperVirtualPre(virtualType),
                 returnType_.txt,
                 " ",
                 name_.str,
                 format("(%s)", paramRange.joinParams),
                 helperConst(isConst),
                 helperVirtualPost(virtualType)
                )
            .joiner()
            .text;
        // dfmt on
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.txt.length > 0);

        foreach (p; params_) {
            assertVisit(p);
        }
    }
}

pure @safe nothrow struct CppMethodOp {
    private CxReturnType returnType_;

    @disable this();

    this(const CppMethodName name, const CxParam[] params, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.returnType_ = return_type;
        this.accessType_ = access;
        this.params_ = params.dup;

        import std.typecons : TypedefType;

        this.isConst_ = cast(TypedefType!CppConstMethod) const_;
        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;
    }

    /// Operator with no parameters.
    this(const CppMethodName name, const CxReturnType return_type, const CppAccess access,
            const CppConstMethod const_, const CppVirtualMethod virtual) {
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

const:

    string toString() {
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only;

        // dfmt off
        return
            only(
                 helperVirtualPre(virtualType),
                 returnType_.txt,
                 " ",
                 name_.str,
                 format("(%s)", paramRange.joinParams),
                 helperConst(isConst),
                 helperVirtualPost(virtualType),
                 // distinguish an operator from a normal method
                 " /* operator */"
                )
            .joiner()
            .text;
        // dfmt on
    }

    @property {
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

        foreach (p; params_) {
            assertVisit(p);
        }
    }
}

pure @safe nothrow struct CppInherit {
    private {
        CppAccess access_;
        CppClassName name_;
        CppNsStack ns;
    }

    @disable this();

    this(CppClassName name, CppAccess access) {
        this.name_ = name;
        this.access_ = access;
    }

    void put(CppNs ns) {
        this.ns ~= ns;
    }

    auto nsRange() @nogc @safe pure nothrow {
        return arrayRange(ns);
    }

const:

    auto toString() {
        import std.algorithm : map, joiner;
        import std.range : chain, only;
        import std.array : Appender, appender;
        import std.typecons : TypedefType;
        import std.string : toLower;
        import std.conv : to, text;

        auto app = appender!string();
        app.put(to!string(cast(TypedefType!CppAccess) access_).toLower);
        app.put(" ");

        // dfmt off
        app.put(chain(ns.map!(a => cast(string) a),
                      only(cast(string) name_))
                .joiner("::")
                .text()
                );
        // dfmt on

        return app.data;
    }

    invariant {
        assert(name_.length > 0);
        foreach (n; ns) {
            assert(n.length > 0);
        }
    }

    @property {
        auto name() {
            return this.name_;
        }

        auto access() {
            return access_;
        }
    }
}

pure @safe nothrow struct CppClass {
    import std.variant : Algebraic, visit;
    import std.typecons : TypedefType;

    alias CppFunc = Algebraic!(CppMethod, CppMethodOp, CppCtor, CppDtor);

    private {
        CppClassName name_;
        CppInherit[] inherits_;
        CppNsStack reside_in_ns;

        VirtualType isVirtual_ = VirtualType.Unknown;

        CppFunc[] methods_pub;
        CppFunc[] methods_prot;
        CppFunc[] methods_priv;

        CppClass[] classes_pub;
        CppClass[] classes_prot;
        CppClass[] classes_priv;

        string[] cmnt;
    }

    mixin mixinUniqueId;
    mixin mixinKind;
    mixin mixinSourceLocation;

    @disable this();

    /** Duplicate an existing classes.
     * TODO also duplicate the dynamic arrays. For now it is "ok" to reuse
     * them. But the duplication should really be done to ensure stability.
     * Params:
     *  other = class to duplicate.
     */
    this(CppClass other) {
        this = other;
    }

    this(const CppClassName name, const CxLocation loc,
            const CppInherit[] inherits, const CppNsStack ns)
    out {
        assert(name_.length > 0);
    }
    body {
        this.name_ = name;
        this.reside_in_ns = ns.dup;

        () @trusted{ inherits_ = (cast(CppInherit[]) inherits).dup; }();

        setLocation(loc);

        ///TODO consider update so the identifier also depend on the namespace.
        setUniqueId(this.name_.str);
    }

    //TODO remove
    this(const CppClassName name, const CxLocation loc, const CppInherit[] inherits)
    out {
        assert(name_.length > 0);
    }
    body {
        this(name, loc, inherits, CppNsStack.init);
    }

    //TODO remove
    this(const CppClassName name, const CxLocation loc)
    out {
        assert(name_.length > 0);
    }
    body {
        this(name, loc, CppInherit[].init, CppNsStack.init);
    }

    //TODO remove
    this(const CppClassName name)
    out {
        assert(name_.length > 0);
    }
    body {
        this(name, CxLocation("noloc", 0, 0), CppInherit[].init, CppNsStack.init);
    }

    void put(T)(T func) @trusted
            if (is(T == CppMethod) || is(T == CppCtor) || is(T == CppDtor) || is(T == CppMethodOp)) {
        auto f = CppFunc(func);

        final switch (cast(TypedefType!CppAccess) func.accessType) {
        case AccessType.Public:
            methods_pub ~= f;
            break;
        case AccessType.Protected:
            methods_prot ~= f;
            break;
        case AccessType.Private:
            methods_priv ~= f;
            break;
        }

        isVirtual_ = analyzeVirtuality(isVirtual_, f);
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

    /** Add a comment string for the class.
     *
     * Params:
     *  comment = a oneline comment, must NOT end with newline
     */
    void put(string comment) {
        cmnt ~= comment;
    }

    void put(CppInherit inh) {
        inherits_ ~= inh;
    }

    auto inheritRange() @nogc {
        return arrayRange(inherits_);
    }

    auto methodRange() @nogc {
        import std.range : chain;

        return chain(methods_pub, methods_prot, methods_priv);
    }

    auto methodPublicRange() @nogc {
        return arrayRange(methods_pub);
    }

    auto methodProtectedRange() @nogc {
        return arrayRange(methods_prot);
    }

    auto methodPrivateRange() @nogc {
        return arrayRange(methods_priv);
    }

    auto classRange() @nogc {
        import std.range : chain;

        return chain(classes_pub, classes_prot, classes_priv);
    }

    auto classPublicRange() @nogc {
        return arrayRange(classes_pub);
    }

    auto classProtectedRange() @nogc {
        return arrayRange(classes_prot);
    }

    auto classPrivateRange() @nogc {
        return arrayRange(classes_priv);
    }

    /** Traverse stack from top to bottom.
     * The implementation of the stack is such that new elements are appended
     * to the end. Therefor the range normal direction is from the end of the
     * array to the beginning.
     */
    auto nsNestingRange() @nogc {
        import std.range : retro;

        return arrayRange(reside_in_ns).retro;
    }

    auto commentRange() @nogc {
        return arrayRange(cmnt);
    }

const:

    string toString() {
        static string funcToString(CppFunc func) @trusted {
            //dfmt off
            return "  " ~ func.visit!((CppMethod a) => a.toString,
                                      (CppMethodOp a) => a.toString,
                                      (CppCtor a) => a.toString,
                                      (CppDtor a) => a.toString);
            //dfmt on
        }

        import std.algorithm : map, joiner;
        import std.ascii : newline;
        import std.conv : to, text;
        import std.format : format;
        import std.range : takeOne, only, chain, takeOne, repeat, roundRobin,
            take;
        import std.string : toLower;

        // dfmt off
        auto begin_class =
            chain(
                  only("class", name_.str).joiner(" "),
                  inherits.takeOne.map!(a => " : ").joiner(),
                  inherits.map!(a => a.toString).joiner(", "), // separate inherit statements
                  only(" { // isVirtual", to!string(virtualType), location.toString).joiner(" ")
                 );
        auto end_class =
            chain(
                  only("}; //Class:").joiner(),
                  reside_in_ns.map!(a => cast(string) a).joiner("::"),
                  reside_in_ns.takeOne.map!(a => "::").joiner(),
                  only(name_.str).joiner()
                 );

        return
            chain(
                  cmnt.map!(a => format("// %s", a)).joiner(newline),
                  begin_class, newline, // <- not a typo, easier to see newline
                  // methods
                  methods_pub.takeOne.map!(a => "public:" ~ newline).joiner(),
                  methods_pub.map!funcToString.roundRobin((";" ~ newline).repeat.take(methods_pub.length)).joiner(),
                  methods_prot.takeOne.map!(a => "protected:" ~ newline).joiner(),
                  methods_prot.map!funcToString.roundRobin((";" ~ newline).repeat.take(methods_prot.length)).joiner(),
                  methods_priv.takeOne.map!(a => "private:" ~ newline).joiner(),
                  methods_priv.map!funcToString.roundRobin((";" ~ newline).repeat.take(methods_priv.length)).joiner(),
                  // classes
                  classes_pub.takeOne.map!(a => "public:" ~ newline).joiner(),
                  classes_pub.map!(a => a.toString).roundRobin(newline.repeat.take(classes_pub.length)).joiner(),
                  classes_prot.takeOne.map!(a => "protected:" ~ newline).joiner(),
                  classes_prot.map!(a => a.toString).roundRobin(newline.repeat.take(classes_prot.length)).joiner(),
                  classes_priv.takeOne.map!(a => "private:" ~ newline).joiner(),
                  classes_priv.map!(a => a.toString).roundRobin(newline.repeat.take(classes_priv.length)).joiner(),
                  end_class
                 )
            .text;
        // dfmt on
    }

    invariant() {
        foreach (i; inherits_) {
            assert(i.name.length > 0);
        }
    }

    @property {
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

        auto resideInNs() {
            return reside_in_ns;
        }
    }
}

// Clang have no function that says if a class is virtual/pure virtual.
// So have to post process.
private VirtualType analyzeVirtuality(T)(in VirtualType current, T p) @safe {
    import std.algorithm : among;

    struct Rval {
        enum Type {
            Normal,
            Ctor,
            Dtor
        }

        VirtualType value;
        Type t;
    }

    static auto getVirt(T func) @trusted {
        import std.variant : visit;

        //dfmt off
        return func.visit!((CppMethod a) => Rval(a.virtualType(), Rval.Type.Normal),
                           (CppMethodOp a) => Rval(a.virtualType(), Rval.Type.Normal),
                           (CppCtor a) => Rval(VirtualType.No, Rval.Type.Ctor),
                           (CppDtor a) => Rval(a.virtualType(), Rval.Type.Dtor));
        //dfmt on
    }

    VirtualType r = current;
    auto mVirt = getVirt(p);

    final switch (current) {
    case VirtualType.Pure:
        // a non-virtual destructor lowers purity
        if (mVirt.t == Rval.Type.Dtor && mVirt.value == VirtualType.No) {
            r = VirtualType.Yes;
        } else if (mVirt.t == Rval.Type.Normal && mVirt.value == VirtualType.Yes) {
            r = VirtualType.Yes;
        }
        break;
    case VirtualType.Yes:
        // one or more methods are virtual or pure, stay at this state
        break;
    case VirtualType.No:
        if (mVirt.t.among(Rval.Type.Normal, Rval.Type.Dtor)
                && mVirt.value.among(VirtualType.Pure, VirtualType.Yes)) {
            r = VirtualType.Yes;
        }
        break;
    case VirtualType.Unknown:
        // ctor cannot affect purity evaluation
        if (mVirt.t == Rval.Type.Dtor
                && mVirt.value.among(VirtualType.Pure, VirtualType.Yes)) {
            r = VirtualType.Pure;
        } else if (mVirt.t != Rval.Type.Ctor) {
            r = mVirt.value;
        }
        break;
    }

    debug {
        import std.conv : to;

        logger.trace(p.type, ":", to!string(mVirt), ":",
                to!string(current), "->", to!string(r));
    }

    return r;
}

pure @safe nothrow struct CppNamespace {
    private {
        bool isAnonymous_;
        CppNs name_;

        CppNsStack stack;
        CppClass[] classes;
        CFunction[] funcs;
        CppNamespace[] namespaces;
        CxGlobalVariable[] globals;
    }

    @disable this();

    mixin mixinKind;

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
    auto nsNestingRange() @nogc {
        import std.range : retro;

        return arrayRange(stack).retro;
    }

    auto classRange() @nogc {
        return arrayRange(classes);
    }

    auto funcRange() @nogc {
        return arrayRange(funcs);
    }

    auto namespaceRange() @nogc {
        return arrayRange(namespaces);
    }

    auto globalRange() @nogc {
        return arrayRange(globals);
    }

const:

    string toString() {
        import std.algorithm : map, joiner;
        import std.ascii : newline;
        import std.range : takeOne, only, chain, retro;
        import std.conv : text;
        import std.format : format;

        auto ns_top_name = stack.retro.takeOne.map!(a => cast(string) a).joiner();
        auto ns_full_name = stack.map!(a => cast(string) a).joiner("::");

        // dfmt off
        return chain(
                     only(format("namespace %s { //%s", ns_top_name, ns_full_name)),
                     globals.map!(a => a.toString),
                     funcs.map!(a => a.toString),
                     classes.map!(a => a.toString),
                     namespaces.map!(a => a.toString),
                     only(format("} //NS:%s", ns_top_name))
                     )
            .joiner(newline)
            .text;
        // dfmt on
    }

    @property {
        auto isAnonymous() {
            return isAnonymous_;
        }

        auto name() {
            return name_;
        }

        auto resideInNs() {
            return stack;
        }
    }
}

pure @safe nothrow struct CppRoot {
    private {
        CppNamespace[] ns;
        CppClass[] classes;
        CFunction[] funcs;
        CxGlobalVariable[] globals;
    }

    mixin mixinSourceLocation;

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

    auto namespaceRange() @nogc {
        return arrayRange(ns);
    }

    auto classRange() @nogc {
        return arrayRange(classes);
    }

    auto funcRange() @nogc {
        return arrayRange(funcs);
    }

    auto globalRange() @nogc {
        return arrayRange(globals);
    }

const:

    string toString() {
        import std.ascii : newline;
        import std.algorithm : map, joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : takeOne, only, chain, retro;

        // dfmt on
        return chain(only(format("// %s", location().toString)),
                globals.takeOne.map!(a => ""), // newline
                globals.map!(a => a.toString),
                funcs.takeOne.map!(a => ""), // newline
                funcs.map!(a => a.toString),
                classes.takeOne.map!(a => ""), // newline
                classes.map!(a => a.toString),
                ns.takeOne.map!(a => ""), // newline
                ns.map!(a => a.toString), only("")).joiner(newline).text;
        // dfmt off
    }
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
    shouldEqual(m.params_.length, 0);
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

    shouldEqualPretty(c.toString, "class Foo { // isVirtual Yes File:noloc Line:0 Column:0
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

@Name("should be a class in a ns in the comment")
unittest {
    CppNsStack ns = [CppNs("a_ns"), CppNs("another_ns")];
    auto c = CppClass(CppClassName("A_Class"), dummyLoc, CppInherit[].init, ns);

    shouldEqualPretty(c.toString,
                      "class A_Class { // isVirtual Unknown File:a.h Line:123 Column:45
}; //Class:a_ns::another_ns::A_Class"
                      );

}

@Name("should contain the inherited classes")
unittest {
    CppInherit[] inherit;
    inherit ~= CppInherit(CppClassName("pub"), CppAccess(AccessType.Public));
    inherit ~= CppInherit(CppClassName("prot"), CppAccess(AccessType.Protected));
    inherit ~= CppInherit(CppClassName("priv"), CppAccess(AccessType.Private));

    auto c = CppClass(CppClassName("Foo"), dummyLoc, inherit);

    shouldEqualPretty(
        c.toString,
        "class Foo : public pub, protected prot, private priv { // isVirtual Unknown File:a.h Line:123 Column:45
}; //Class:Foo");
}

@Name("should contain nested classes")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    c.put(CppClass(CppClassName("Pub")), AccessType.Public);
    c.put(CppClass(CppClassName("Prot")), AccessType.Protected);
    c.put(CppClass(CppClassName("Priv")), AccessType.Private);

    shouldEqualPretty(c.toString, "class Foo { // isVirtual Unknown File:noloc Line:0 Column:0
public:
class Pub { // isVirtual Unknown File:noloc Line:0 Column:0
}; //Class:Pub
protected:
class Prot { // isVirtual Unknown File:noloc Line:0 Column:0
}; //Class:Prot
private:
class Priv { // isVirtual Unknown File:noloc Line:0 Column:0
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

@Name("should be proper access specifiers for a inherit reference, no nesting")
unittest {
    auto ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Public));
    shouldEqual("public Class", ih.toString);

    ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Protected));
    shouldEqual("protected Class", ih.toString);

    ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Private));
    shouldEqual("private Class", ih.toString);
}

@Name("should be a inheritances of a class in namespaces")
unittest {
    auto ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Public));
    ih.put(CppNs("ns1"));
    ih.toString.shouldEqual("public ns1::Class");

    ih.put(CppNs("ns2"));
    ih.toString.shouldEqual("public ns1::ns2::Class");

    ih.put(CppNs("ns3"));
    ih.toString.shouldEqual("public ns1::ns2::ns3::Class");
}

@Name("should be a class that inherits")
unittest {
    auto ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Public));
    ih.put(CppNs("ns1"));

    auto c = CppClass(CppClassName("A"));
    c.put(ih);

    c.toString.shouldEqualPretty(
        "class A : public ns1::Class { // isVirtual Unknown File:noloc Line:0 Column:0
}; //Class:A");
}
