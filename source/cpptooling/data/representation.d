/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Structuraly represents the semantic-centric view of of C/C++ code.

The guiding principle for this module is: "Correct by construction".
 * After the data is created it should be "correct".
 * As far as possible avoid runtime errors.
Therefor the default c'tor is disabled.

Structs was chosen instead of classes to:
 * ensure allocation on the stack.
 * lower the GC pressure.
 * dynamic dispatch isn't needed.
 * value semantics.

Design rules for Structural representation.
shall:
 * toString functions shall never append a newline as the last character.
 * toString(..., FormatSpec!Char fmt) shall have a %u when the struct has a USR.
 * all c'tor parameters shall be const.
 * members are declared at the top.
    Rationale const: (The ':' is not a typo) can affect var members thus all
    member shall be defined after imports.
when applicable:
 * attributes "@safe" for the struct.
 * Add mixin for Id when the need arise.

TODO Implement uniqueness for namespaces and classes via e.g. RedBlackTree's
*/
module cpptooling.data.representation;

import std.array : Appender;
import std.format : format, FormatSpec;
import std.range : isInputRange;
import std.typecons : Tuple, Flag, Yes, No, Nullable;
import std.variant : Algebraic;
import logger = std.experimental.logger;

public import cpptooling.data.type;

import cpptooling.analyzer.type;
import cpptooling.data.symbol.types : USRType;
import cpptooling.utility.unqual : Unqual;

static import cpptooling.data.class_classification;

version (unittest) {
    import test.extra_should : shouldEqualPretty;
    import unit_threaded : Name;
    import unit_threaded : shouldBeTrue, shouldEqual, shouldBeGreaterThan;
    import unit_threaded : writelnUt;

    private enum dummyUSR = USRType("dummyUSR");
} else {
    private struct Name {
        string name_;
    }
}

private size_t _nextUSR;

static this() {
    // Keeping it fixed to make it easier to debug, read the logs. Aka
    // reproduce the result.
    _nextUSR = 42;
}

/** Construct a USR that is ensured to be unique.
 *
 * The USR start with a number which is an illegal symbol in C/C++.
 * Which should result in them never clashing with those from sources derived
 * from source code.
 */
USRType makeUniqueUSR() @safe nothrow {
    import std.conv : text;

    if (_nextUSR == size_t.max) {
        _nextUSR = size_t.min;
    }

    _nextUSR += 1;

    return USRType(text(_nextUSR));
}

void funcToString(Writer, Char)(const(CppClass.CppFunc) func, scope Writer w, in Char[] fmt) @trusted {
    import std.format : formattedWrite;
    import std.variant : visit;

    //dfmt off
    func.visit!((const(CppMethod) a) => formattedWrite(w, fmt, a),
                (const(CppMethodOp) a) => formattedWrite(w, fmt, a),
                (const(CppCtor) a) => formattedWrite(w, fmt, a),
                (const(CppDtor) a) => formattedWrite(w, fmt, a));
    //dfmt on
}

string funcToString(const(CppClass.CppFunc) func) @safe {
    import std.exception : assumeUnique;

    char[] buf;
    buf.reserve(100);
    funcToString(func, (const(char)[] s) { buf ~= s; }, "%s");
    auto trustedUnique(T)(T t) @trusted {
        return assumeUnique(t);
    }

    return trustedUnique(buf);
}

/// Convert a CxParam to a string.
string paramTypeToString(CxParam p, string id = "") @trusted {
    import std.variant : visit;

    // dfmt off
    return p.visit!(
        (TypeKindVariable tk) { return tk.type.toStringDecl(id); },
        (TypeKindAttr t) { return t.toStringDecl; },
        (VariadicType a) { return "..."; }
        );
    // dfmt on
}

// string mixin
private string standardToString() {
    return q{
    string toString()() const {
        import std.format : FormatSpec;
        import std.exception : assumeUnique;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
    };
}

private size_t makeHash(string identifier) @safe pure nothrow @nogc {
    import std.digest.crc;

    size_t value = 0;

    if (identifier is null)
        return value;
    ubyte[4] hash = crc32Of(identifier);
    return value ^ ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
}

/// Expects a toString function where it is mixed in.
/// base value for hash is 0 to force deterministic hashes. Use the pointer for
/// unique between objects.
private template mixinUniqueId(IDType) if (is(IDType == size_t) || is(IDType == string)) {
    //TODO add check to see that this do NOT already have id_.

    private IDType id_;

@safe:

    static if (is(IDType == size_t)) {
        private void setUniqueId(string identifier) {
            this.id_ = makeHash(identifier);
        }
    } else static if (is(IDType == string)) {
        private void setUniqueId(Char)(Char[] identifier) {
            this.id_ = identifier.idup;
        }
    } else {
        static assert(false, "IDType must be either size_t or string");
    }

    IDType id() const {
        return id_;
    }

    int opCmp(T : typeof(this))(auto ref const T rhs) const {
        return this.id_ < rhs.id();
    }

    bool opEquals(T : typeof(this))(auto ref const T rhs) const {
        return this.id_ == rhs.id();
    }
}

/// User defined kind to differeniate structs of the same type.
private template mixinKind() {
    private int kind_;

@safe:

    void setKind(int kind) {
        this.kind_ = kind;
    }

    auto kind() const {
        return kind_;
    }
}

/// Convert a CxParam to a string.
string toInternal(CxParam p) @trusted {
    import std.variant : visit;

    // dfmt off
    return p.visit!(
        (TypeKindVariable tk) {return tk.type.toStringDecl(tk.name);},
        (TypeKindAttr t) { return t.toStringDecl; },
        (VariadicType a) { return "..."; }
        );
    // dfmt on
}

/// Convert a TypeKindVariable to a string.
string toInternal(TypeKindVariable tk) @trusted {
    return tk.type.toStringDecl(tk.name);
}

/// Join a range of CxParams to a string separated by ", ".
string joinParams(const(CxParam)[] r) @safe {
    import std.algorithm : joiner, map;
    import std.conv : text;
    import std.range : enumerate;

    static string getTypeName(const CxParam p, ulong uid) @trusted {
        import std.variant : visit;

        // dfmt off
        auto x = p.visit!(
            (const TypeKindVariable t) {return t.type.toStringDecl(t.name);},
            (const TypeKindAttr t) { return t.toStringDecl("x" ~ text(uid)); },
            (const VariadicType a) { return "..."; }
            );
        // dfmt on
        return x;
    }

    // dfmt off
    return r
        .enumerate
        .map!(a => getTypeName(a.value, a.index))
        .joiner(", ")
        .text();
    // dfmt on
}

/// Join a range of CxParams by extracting the parameter names.
string joinParamNames(T)(T r) @safe if (isInputRange!T) {
    import std.algorithm : joiner, map, filter;
    import std.conv : text;
    import std.range : enumerate;

    static string getName(const CxParam p, ulong uid) @trusted {
        import std.variant : visit;

        // dfmt off
        return p.visit!(
            (const TypeKindVariable tk) {return tk.name;},
            (const TypeKindAttr t) { return "x" ~ text(uid); },
            (const VariadicType a) { return ""; }
            );
        // dfmt on
    }

    // using cache to avoid getName is called twice.
    // dfmt off
    return r
        .enumerate
        .map!(a => getName(a.value, a.index))
        .filter!(a => a.length > 0)
        .joiner(", ").text();
    // dfmt on
}

/// Get the name of a C++ method.
string getName()(ref const(CppClass.CppFunc) method) @trusted {
    import std.variant : visit;

    // dfmt off
    return method.visit!(
                         (const CppMethod m) => m.name,
                         (const CppMethodOp m) => "",
                         (const CppCtor m) => m.name,
                         (const CppDtor m) => m.name);
    // dfmt on
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

private void assertVisit(ref const(CxParam) p) @trusted {
    import std.variant : visit;

    // dfmt off
    p.visit!(
        (const TypeKindVariable tk) { assert(tk.name.length > 0);
                                      assert(tk.type.toStringDecl.length > 0);},
        (const TypeKindAttr t)      { assert(t.toStringDecl.length > 0); },
        (const VariadicType a)      {});
    // dfmt on
}

struct CxGlobalVariable {
    mixin mixinUniqueId!string;

    private TypeKindVariable variable;

    Nullable!USRType usr;

    invariant {
        assert(usr.isNull || usr.length > 0);
    }

    /**
     * do NOT use the usr from var.type.kind.usr, it is for the type not the
     * instance.
     */
    this(USRType usr, TypeKindVariable var) @safe pure nothrow {
        this.usr = usr;
        this.variable = var;
        setUniqueId(variable.name);
    }

    this(USRType usr, TypeKindAttr type, CppVariable name) @safe pure nothrow {
        this(usr, TypeKindVariable(type, name));
    }

const:

    mixin(standardToString);

    /// If formatSpec is "%u" then the USR will be put as a comment.
    void toString(Writer, Char)(scope Writer sink, FormatSpec!Char fmt)
    in {
        import std.algorithm : among;

        // see switch stmt in body for explanation.
        assert(!variable.type.kind.info.kind.among(TypeKind.Info.Kind.ctor,
                TypeKind.Info.Kind.dtor));
    }
    body {
        import std.algorithm : map, copy;
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.range : put;
        import cpptooling.analyzer.type : TypeKind;

        final switch (variable.type.kind.info.kind) with (TypeKind.Info) {
        case Kind.record:
        case Kind.func:
        case Kind.funcPtr:
        case Kind.funcSignature:
        case Kind.primitive:
        case Kind.simple:
        case Kind.typeRef:
        case Kind.array:
        case Kind.pointer:
            formattedWrite(sink, "%s;", variable.type.toStringDecl(variable.name));
            if (!usr.isNull && fmt.spec == 'u') {
                put(sink, " // ");
                put(sink, usr);
            }
            break;
        case Kind.ctor:
            logger.error("Assumption broken. A global variable with the type of a Constructor");
            break;
        case Kind.dtor:
            logger.error("Assumption broken. A global variable with the type of a Destructor");
            break;
        case Kind.null_:
            logger.error("Type of global variable is null. Identifier ",
                    variable.name);
            break;
        }
    }

@safe pure nothrow:

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

struct CppMethodGeneric {
    template Parameters() {
        void put(const CxParam p) {
            params_ ~= p;
        }

        auto paramRange() const @nogc @safe pure nothrow {
            return params_;
        }

        private CxParam[] params_;
    }

    /** Common properties for c'tor, d'tor, methods and operators.
     *
     * Defines the needed variables.
     * Expecting them to be set in c'tors.
     */
    template BaseProperties() {
        import std.typecons : Nullable;

        const pure @nogc nothrow {
            bool isVirtual() {
                import std.algorithm : among;

                with (MemberVirtualType) {
                    return classification_.among(Virtual, Pure) != 0;
                }
            }

            bool isPure() {
                with (MemberVirtualType) {
                    return classification_ == Pure;
                }
            }

            MemberVirtualType classification() {
                return classification_;
            }

            CppAccess accessType() {
                return accessType_;
            }

            CppMethodName name() {
                return name_;
            }
        }

        private Nullable!MemberVirtualType classification_;
        private CppAccess accessType_;
        private Nullable!CppMethodName name_;
    }

    /** Properties used by methods and operators.
     *
     * Defines the needed variables.
     * Expecting them to be set in c'tors.
     */
    template MethodProperties() {
        const pure @nogc nothrow {
            bool isConst() {
                return isConst_;
            }

            CxReturnType returnType() {
                return returnType_;
            }
        }

        private bool isConst_;
        private CxReturnType returnType_;
    }

    /// Helper for converting virtual type to string
    template StringHelperVirtual() {
        static string helperVirtualPre(MemberVirtualType pre) @safe pure nothrow @nogc {
            switch (pre) {
            case MemberVirtualType.Virtual:
            case MemberVirtualType.Pure:
                return "virtual ";
            default:
                return "";
            }
        }

        static string helperVirtualPost(MemberVirtualType post) @safe pure nothrow @nogc {
            switch (post) {
            case MemberVirtualType.Pure:
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
struct CFunction {
    mixin mixinUniqueId!string;

    Nullable!USRType usr;

    private {
        CFunctionName name_;
        CxParam[] params;
        CxReturnType returnType_;
        VariadicType isVariadic_;
        StorageClass storageClass_;
    }

    invariant() {
        if (!usr.isNull) {
            assert(usr.length > 0);
            assert(name_.length > 0);
            assert(returnType_.toStringDecl.length > 0);

            foreach (p; params) {
                assertVisit(p);
            }
        }
    }

    /// C function representation.
    this(const USRType usr, const CFunctionName name, const CxParam[] params_,
            const CxReturnType return_type, const VariadicType is_variadic,
            const StorageClass storage_class) @trusted {
        this.usr = usr;
        this.name_ = name;
        this.returnType_ = return_type;
        this.isVariadic_ = is_variadic;
        this.storageClass_ = storage_class;

        this.params = params_.dup;

        setUniqueId(signatureToString);
    }

    /// Function with no parameters.
    this(USRType usr, const CFunctionName name, const CxReturnType return_type) @trusted {
        this(usr, name, CxParam[].init, return_type, VariadicType.no, StorageClass.None);
    }

    /// Function with no parameters and returning void.
    this(USRType usr, const CFunctionName name) @trusted {
        auto void_ = CxReturnType(makeSimple("void"));
        this(usr, name, CxParam[].init, void_, VariadicType.no, StorageClass.None);
    }

    void toString(Writer, Char)(scope Writer sink, FormatSpec!Char fmt) const {
        import std.conv : to;
        import std.format : formattedWrite;
        import std.range : put;

        formattedWrite(sink, "%s; // %s", signatureToString(), to!string(storageClass));

        if (!usr.isNull && fmt.spec == 'u') {
            put(sink, " ");
            put(sink, usr);
        }
    }

@safe const:

    private string signatureToString() {
        import std.array : Appender, appender;
        import std.format : formattedWrite;

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s)", returnType.toStringDecl, name, paramRange.joinParams);
        return rval.data;
    }

    mixin(standardToString);

nothrow pure @nogc:

    /// A range over the parameters of the function.
    auto paramRange() {
        return params;
    }

    CxReturnType returnType() {
        return returnType_;
    }

    auto name() {
        return name_;
    }

    StorageClass storageClass() {
        return storageClass_;
    }

    /// If the function is variadic, aka have a parameter with "...".
    bool isVariadic() {
        return VariadicType.yes == isVariadic_;
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
@safe struct CppCtor {
    mixin mixinUniqueId!string;
    mixin CppMethodGeneric.Parameters;

    Nullable!USRType usr;

    private {
        CppAccess accessType_;
        Nullable!CppMethodName name_;
    }

    invariant() {
        if (!name_.isNull) {
            assert(usr.isNull || usr.length > 0);
            assert(name_.length > 0);
            foreach (p; params_) {
                assertVisit(p);
            }
        }
    }

    this(const USRType usr, const CppMethodName name, const CxParam[] params, const CppAccess access) {
        this.usr = usr;
        this.name_ = name;
        this.accessType_ = access;
        this.params_ = params.dup;

        setUniqueId(toString);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formattedWrite;

        formattedWrite(w, "%s(%s);", name_, paramRange.joinParams);
        if (!usr.isNull && fmt.spec == 'u') {
            formattedWrite(w, " // %s", usr);
        }
    }

const:

    mixin(standardToString);

    auto accessType() {
        return accessType_;
    }

    auto name() {
        return name_;
    }
}

@safe struct CppDtor {
    mixin mixinUniqueId!string;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.StringHelperVirtual;

    Nullable!USRType usr;

    invariant() {
        if (!name_.isNull) {
            assert(usr.isNull || usr.length > 0);
            assert(name_.length > 0);
            assert(classification_ != MemberVirtualType.Unknown);
        }
    }

    this(const USRType usr, const CppMethodName name, const CppAccess access,
            const CppVirtualMethod virtual) {
        this.usr = usr;
        this.classification_ = virtual;
        this.accessType_ = access;
        this.name_ = name;

        setUniqueId(name_);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formattedWrite;

        formattedWrite(w, "%s%s();", helperVirtualPre(classification_), name_);
        if (!usr.isNull && fmt.spec == 'u') {
            formattedWrite(w, " // %s", usr);
        }
    }

    mixin(standardToString);
}

@safe struct CppMethod {
    mixin mixinUniqueId!string;
    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.MethodProperties;

    Nullable!USRType usr;

    invariant {
        if (!name_.isNull) {
            assert(usr.isNull || usr.length > 0);
            assert(name_.length > 0);
            assert(returnType_.toStringDecl.length > 0);
            assert(classification_ != MemberVirtualType.Unknown);
            foreach (p; params_) {
                assertVisit(p);
            }
        }
    }

    this(const USRType usr, const CppMethodName name, const CxParam[] params, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) @safe {
        this.usr = usr;
        this.classification_ = virtual;
        this.accessType_ = access;
        this.name_ = name;
        this.returnType_ = return_type;
        this.isConst_ = const_;

        this.params_ = params.dup;

        char[] buf;
        buf.reserve(100);
        signatureToString((const(char)[] s) { buf ~= s; });
        setUniqueId(buf);
    }

    /// Function with no parameters.
    this(USRType usr, const CppMethodName name, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) @safe {
        this(usr, name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(USRType usr, const CppMethodName name, const CppAccess access, const CppConstMethod const_ = CppConstMethod(false),
            const CppVirtualMethod virtual = CppVirtualMethod(MemberVirtualType.Normal)) @safe {
        auto void_ = CxReturnType(makeSimple("void"));
        this(usr, name, CxParam[].init, void_, access, const_, virtual);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) @safe const {
        import std.range.primitives : put;

        put(w, helperVirtualPre(classification_));
        put(w, returnType_.toStringDecl);
        put(w, " ");
        signatureToString(w);
        put(w, helperVirtualPost(classification_));
        put(w, ";");

        if (!usr.isNull && fmt.spec == 'u') {
            put(w, " // ");
            put(w, usr);
        }
    }

    mixin(standardToString);

    private void signatureToString(Writer)(scope Writer w) const {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        put(w, name_);
        formattedWrite(w, "(%s)", paramRange.joinParams);
        put(w, helperConst(isConst));
    }
}

@safe struct CppMethodOp {
    mixin mixinUniqueId!string;
    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.MethodProperties;

    Nullable!USRType usr;

    invariant() {
        if (!name_.isNull) {
            assert(name_.length > 0);
            assert(returnType_.toStringDecl.length > 0);
            assert(classification_ != MemberVirtualType.Unknown);

            foreach (p; params_) {
                assertVisit(p);
            }
        }
    }

    this(const USRType usr, const CppMethodName name, const CxParam[] params, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) @safe {
        this.usr = usr;
        this.classification_ = virtual;
        this.accessType_ = access;
        this.name_ = name;
        this.isConst_ = const_;
        this.returnType_ = return_type;

        this.params_ = params.dup;
    }

    /// Operator with no parameters.
    this(const USRType usr, const CppMethodName name, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) @safe {
        this(usr, name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Operator with no parameters and returning void.
    this(const USRType usr, const CppMethodName name, const CppAccess access,
            const CppConstMethod const_ = CppConstMethod(false),
            const CppVirtualMethod virtual = CppVirtualMethod(MemberVirtualType.Normal)) @safe {
        auto void_ = CxReturnType(makeSimple("void"));
        this(usr, name, CxParam[].init, void_, access, const_, virtual);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.range.primitives : put;

        put(w, helperVirtualPre(classification_));
        put(w, returnType_.toStringDecl);
        put(w, " ");
        put(w, signatureToString);
        put(w, helperVirtualPost(classification_));
        put(w, ";");

        if (!usr.isNull && fmt.spec == 'u') {
            put(w, " // ");
            put(w, usr);
        }
    }

@safe const:

    /// Signature of the method.
    private string signatureToString() {
        import std.format : format;

        return format("%s(%s)%s", name_, paramRange.joinParams, helperConst(isConst));
    }

    mixin(standardToString);

    /// The operator type, aka in C++ the part after "operator"
    auto op()
    in {
        assert(name_.length > 8);
    }
    body {
        return CppMethodName((cast(string) name_)[8 .. $]);
    }
}

@safe struct CppInherit {
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    Nullable!USRType usr;

    private {
        CppAccess access_;
        CppClassName name_;
        CppNsStack ns;
    }

    invariant {
        assert(name_.length > 0);
        foreach (n; ns) {
            assert(n.length > 0);
        }
    }

    this(CppClassName name, CppAccess access) {
        this.name_ = name;
        this.access_ = access;
    }

    void put(CppNs ns) {
        this.ns ~= ns;
    }

    auto nsRange() @nogc @safe pure nothrow {
        return ns;
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.conv : to;
        import std.format : formattedWrite;
        import std.range.primitives : put;
        import std.string : toLower;

        put(w, (cast(string) access_).toLower);
        put(w, " ");

        foreach (a; ns) {
            formattedWrite(w, "%s::", a);
        }
        put(w, cast(string) name_);
    }

const:

    mixin(standardToString);

    auto name() {
        return this.name_;
    }

    auto access() {
        return access_;
    }

    FullyQualifiedNameType fullyQualifiedName() const {
        //TODO optimize by only calculating once.
        import std.algorithm : map, joiner;
        import std.range : chain, only;
        import std.conv : text;

        // dfmt off
        auto r = chain(ns.payload.map!(a => cast(string) a),
                       only(cast(string) name_))
            .joiner("::")
            .text();
        return FullyQualifiedNameType(r);
        // dfmt on
    }
}

@safe struct CppClass {
    mixin mixinKind;
    mixin mixinUniqueId!size_t;

    import std.variant : Algebraic, visit;
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    static import cpptooling.data.class_classification;

    alias CppFunc = Algebraic!(CppMethod, CppMethodOp, CppCtor, CppDtor);

    Nullable!USRType usr;

    private {
        CppClassName name_;
        CppInherit[] inherits_;
        CppNsStack reside_in_ns;

        cpptooling.data.class_classification.State classification_;

        CppFunc[] methods_pub;
        CppFunc[] methods_prot;
        CppFunc[] methods_priv;

        CppClass[] classes_pub;
        CppClass[] classes_prot;
        CppClass[] classes_priv;

        TypeKindVariable[] members_pub;
        TypeKindVariable[] members_prot;
        TypeKindVariable[] members_priv;

        string[] comments;
    }

    this(const CppClassName name, const CppInherit[] inherits, const CppNsStack ns)
    out {
        assert(name_.length > 0);
    }
    body {
        this.name_ = name;
        this.reside_in_ns = CppNsStack(ns.dup);

        () @trusted{ inherits_ = (cast(CppInherit[]) inherits).dup; }();

        ///TODO consider update so the identifier also depend on the namespace.
        setUniqueId(this.name_);
    }

    //TODO remove
    this(const CppClassName name, const CppInherit[] inherits)
    out {
        assert(name_.length > 0);
    }
    body {
        this(name, inherits, CppNsStack.init);
    }

    //TODO remove
    this(const CppClassName name)
    out {
        assert(name_.length > 0);
    }
    body {
        this(name, CppInherit[].init, CppNsStack.init);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.algorithm : copy, joiner, map, each;
        import std.ascii : newline;
        import std.conv : to;
        import std.format : formattedWrite;
        import std.range : takeOne, put, save;

        foreach (a; comments) {
            formattedWrite(w, "// %s\n", a);
        }

        formattedWrite(w, "class %s", name_);

        // inheritance
        if (inherits_.length > 0) {
            formattedWrite(w, " : %s", inherits_[0]);
            foreach (a; inherits_[1 .. $]) {
                formattedWrite(w, ", %s", a);
            }
        }
        formattedWrite(w, " { // %s%s", to!string(classification_), newline);

        // debug help
        if (!usr.isNull && fmt.spec == 'u') {
            put(w, " // ");
            put(w, usr);
            put(w, newline);
        }

        // methods
        void dumpMethods(R)(ref R range, string visibility) @safe {
            if (range.length > 0) {
                formattedWrite(w, "%s\n", visibility);
            }

            auto tmp_fmt = ['%', fmt.spec];
            foreach (ref a; range) {
                put(w, "  ");
                a.funcToString(w, tmp_fmt);
                put(w, newline);
            }
        }

        dumpMethods(methods_pub, "public:");
        dumpMethods(methods_prot, "protected:");
        dumpMethods(methods_priv, "private:");

        // members
        void dumpMembers(R)(ref R range, string visibility) {
            if (range.length > 0) {
                formattedWrite(w, "%s\n", visibility);
            }

            foreach (ref a; range) {
                formattedWrite(w, "  %s;\n", toInternal(a));
            }
        }

        dumpMembers(members_pub, "public:");
        dumpMembers(members_prot, "protected:");
        dumpMembers(members_priv, "private:");

        // inner classes
        void dumpClasses(R)(ref R range, string visibility) {
            if (range.length > 0) {
                formattedWrite(w, "%s\n", visibility);
            }

            foreach (a; range) {
                a.toString(w, fmt);
                put(w, newline);
            }
        }

        dumpClasses(classes_pub, "public:");
        dumpClasses(classes_prot, "protected:");
        dumpClasses(classes_priv, "private:");

        // end
        put(w, "}; //Class:");
        reside_in_ns.payload.map!(a => cast(string) a).joiner("::").copy(w);
        reside_in_ns.payload.takeOne.map!(a => "::").copy(w);
        put(w, name_);
    }

    mixin(standardToString);

    void put(T)(T func)
            if (is(Unqual!T == CppMethod) || is(Unqual!T == CppCtor)
                || is(Unqual!T == CppDtor) || is(Unqual!T == CppMethodOp)) {
        auto f = () @trusted{ Unqual!T tmp; tmp = func; return CppFunc(tmp); }();

        final switch (func.accessType) {
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

        classification_ = cpptooling.data.class_classification.classifyClass(classification_,
                f, cast(Flag!"hasMember")(memberRange.length > 0));
    }

    void put(CppFunc f) {
        static void internalPut(T)(ref T class_, CppFunc f) @trusted {
            import std.variant : visit;

            // dfmt off
            f.visit!((CppMethod a) => class_.put(a),
                     (CppMethodOp a) => class_.put(a),
                     (CppCtor a) => class_.put(a),
                     (CppDtor a) => class_.put(a));
            // dfmt on
        }

        internalPut(this, f);
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

    void put(T)(T member_, AccessType accessType) @trusted 
            if (is(T == TypeKindVariable)) {
        final switch (accessType) {
        case AccessType.Public:
            members_pub ~= member_;
            break;
        case AccessType.Protected:
            members_prot ~= member_;
            break;
        case AccessType.Private:
            members_priv ~= member_;
            break;
        }
    }

    /** Add a comment string for the class.
     *
     * Params:
     *  comment = a oneline comment, must NOT end with newline
     */
    void put(string comment) {
        comments ~= comment;
    }

    void put(CppInherit inh) {
        inherits_ ~= inh;
    }

const:

    auto inheritRange() @nogc {
        return inherits_;
    }

    auto methodRange() @nogc {
        import std.range : chain;

        return chain(methods_pub, methods_prot, methods_priv);
    }

    auto methodPublicRange() @nogc {
        return methods_pub;
    }

    auto methodProtectedRange() @nogc {
        return methods_prot;
    }

    auto methodPrivateRange() @nogc {
        return methods_priv;
    }

    auto classRange() @nogc {
        import std.range : chain;

        return chain(classes_pub, classes_prot, classes_priv);
    }

    auto classPublicRange() @nogc {
        return classes_pub;
    }

    auto classProtectedRange() @nogc {
        return classes_prot;
    }

    auto classPrivateRange() @nogc {
        return classes_priv;
    }

    auto memberRange() @nogc {
        import std.range : chain;

        return chain(members_pub, members_prot, members_priv);
    }

    auto memberPublicRange() @nogc {
        return members_pub;
    }

    auto memberProtectedRange() @nogc {
        return members_prot;
    }

    auto memberPrivateRange() @nogc {
        return members_priv;
    }

    /** Traverse stack from top to bottom.
     * The implementation of the stack is such that new elements are appended
     * to the end. Therefor the range normal direction is from the end of the
     * array to the beginning.
     */
    auto nsNestingRange() @nogc {
        import std.range : retro;

        return reside_in_ns.payload.retro;
    }

    auto commentRange() @nogc {
        return comments;
    }

    invariant() {
        //assert(usr.isNull || usr.length > 0);
        foreach (i; inherits_) {
            assert(i.name.length > 0);
        }
    }

    bool isVirtual() {
        import std.algorithm : among;

        with (cpptooling.data.class_classification.State) {
            return classification_.among(Virtual, VirtualDtor, Abstract, Pure) != 0;
        }
    }

    bool isAbstract() {
        with (cpptooling.data.class_classification.State) {
            return classification_ == Abstract;
        }
    }

    bool isPure() {
        import std.algorithm : among;

        with (cpptooling.data.class_classification.State) {
            return classification_.among(VirtualDtor, Pure) != 0;
        }
    }

    auto classification() {
        return classification_;
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

    FullyQualifiedNameType fullyQualifiedName() {
        //TODO optimize by only calculating once.

        import std.array : array;
        import std.algorithm : map, joiner;
        import std.range : takeOne, only, chain, takeOne;
        import std.utf : byChar, toUTF8;

        // dfmt off
        auto fqn = chain(
                         reside_in_ns.payload.map!(a => cast(string) a).joiner("::"),
                         reside_in_ns.payload.takeOne.map!(a => "::").joiner(),
                         only(cast(string) name_).joiner()
                        );
        return FullyQualifiedNameType(fqn.array().toUTF8);
        // dfmt on
    }
}

@safe struct CppNamespace {
    mixin mixinKind;

    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    private {
        CppNs name_;

        CppNsStack stack;
        CppClass[] classes;
        CFunction[] funcs;
        CppNamespace[] namespaces;
        CxGlobalVariable[] globals;
    }

    static auto makeAnonymous() pure nothrow {
        return CppNamespace(CppNsStack.init);
    }

    /// A namespace without any nesting.
    static auto make(CppNs name) pure nothrow {
        return CppNamespace(CppNsStack([name]));
    }

    this(const CppNsStack stack) pure nothrow {
        if (stack.length > 0) {
            this.name_ = stack[$ - 1];
        }
        this.stack = CppNsStack(stack.dup);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.algorithm : map, joiner;
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.meta : AliasSeq;
        import std.range : takeOne, retro, put;

        auto ns_top_name = stack.payload.retro.takeOne.map!(a => cast(string) a).joiner();
        auto ns_full_name = stack.payload.map!(a => cast(string) a).joiner("::");

        formattedWrite(w, "namespace %s { //%s\n", ns_top_name, ns_full_name);

        foreach (range; AliasSeq!("globals[]", "funcs[]", "classes", "namespaces")) {
            foreach (a; mixin(range)) {
                a.toString(w, fmt);
                put(w, newline);
            }
        }

        formattedWrite(w, "} //NS:%s", ns_top_name);
    }

    void put(CFunction f) pure nothrow {
        funcs ~= f;
    }

    void put(CppClass s) pure nothrow {
        classes ~= s;
    }

    void put(CppNamespace ns) pure nothrow {
        namespaces ~= ns;
    }

    void put(CxGlobalVariable g) pure nothrow {
        globals ~= g;
    }

    /** Range of the fully qualified name starting from the top.
     *
     * The top is THIS namespace.
     * So A::B::C would be a range of [C, B, A].
     */
    auto nsNestingRange() @nogc pure nothrow {
        import std.range : retro;

        return stack.payload.retro;
    }

    /// Range data of symbols residing in this namespace.
    auto classRange() @nogc pure nothrow {
        return classes;
    }

    /// Range of free functions residing in this namespace.
    auto funcRange() @nogc pure nothrow {
        return funcs;
    }

    /// Range of namespaces residing in this namespace.
    auto namespaceRange() @nogc pure nothrow {
        return namespaces;
    }

    /// Global variables residing in this namespace.
    auto globalRange() @nogc pure nothrow {
        return globals;
    }

const:

    mixin(standardToString);

    /// If the namespace is anonymous, aka has no name.
    auto isAnonymous() pure nothrow {
        return name_.length == 0;
    }

    /// Name of the namespace
    auto name() pure nothrow {
        return name_;
    }

    /** Range representation of the fully qualified name.
     *
     * TODO change function name, it is the full stack. So fully qualified
     * name.
     */
    auto resideInNs() pure nothrow {
        return stack;
    }

    /** The fully qualified name of where the namespace reside.
     *
     * Example of FQN for C could be A::B::C.
     */
    auto fullyQualifiedName() pure {
        //TODO optimize by only calculating once.

        import std.array : array;
        import std.algorithm : map, joiner;
        import std.utf : toUTF8;

        // dfmt off
        auto fqn = stack.payload.map!(a => cast(string) a).joiner("::");
        return FullyQualifiedNameType(fqn.array().toUTF8);
        // dfmt on
    }
}

/** The root of the data structure of the semantic representation of the
 * analyzed C++ source.
 */
struct CppRoot {
    import std.container : RedBlackTree;

    private {
        CppNamespace[] ns;
        CppClass[] classes;
        RedBlackTree!(CxGlobalVariable, "a.id < b.id") globals;
        RedBlackTree!(CFunction, "a.id < b.id") funcs;
    }

    /// Returns: An initialized CppRoot
    static auto make() @safe {
        import std.container : make;

        CppRoot r;

        r.globals = make!(typeof(this.globals));
        r.funcs = make!(typeof(this.funcs));

        return r;
    }

    /// Recrusive stringify the content for human readability.
    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.ascii : newline;
        import std.meta : AliasSeq;
        import std.range : put;

        foreach (range; AliasSeq!("globals[]", "funcs[]", "classes", "ns")) {
            foreach (a; mixin(range)) {
                a.toString(w, fmt);
                put(w, newline);
            }
        }
    }

@safe:

    /// Put item in storage.
    void put(CFunction f) {
        () @trusted{ funcs.insert(f); }();
    }

    /// ditto
    void put(CppClass s) {
        classes ~= s;
    }

    /// ditto
    void put(CppNamespace ns) {
        this.ns ~= ns;
    }

    /// ditto
    void put(CxGlobalVariable g) {
        () @trusted{ globals.insert(g); }();
    }

    /// Range of contained data.
    auto namespaceRange() @nogc {
        return ns;
    }

    /// ditto
    auto classRange() @nogc {
        return classes;
    }

    /// ditto
    auto funcRange() @nogc {
        return funcs[];
    }

    /// ditto
    auto globalRange() @nogc {
        return globals[];
    }

    /// Cast to string representation
    T opCast(T : string)() const {
        return this.toString;
    }

    mixin(standardToString);
}

@Name("Test of c-function")
unittest {
    { // simple version, no return or parameters.
        auto f = CFunction(dummyUSR, CFunctionName("nothing"));
        shouldEqual(f.returnType.toStringDecl("x"), "void x");
        shouldEqual(format("%u", f), "void nothing(); // None dummyUSR");
    }

    { // extern storage.
        auto f = CFunction(dummyUSR, CFunctionName("nothing"), [],
                CxReturnType(makeSimple("void")), VariadicType.no, StorageClass.Extern);
        shouldEqual(f.returnType.toStringDecl("x"), "void x");
        shouldEqual(format("%u", f), "void nothing(); // Extern dummyUSR");
    }

    { // a return type.
        auto f = CFunction(dummyUSR, CFunctionName("nothing"), CxReturnType(makeSimple("int")));
        shouldEqual(format("%u", f), "int nothing(); // None dummyUSR");
    }

    { // return type and parameters.
        auto p0 = makeCxParam(TypeKindVariable(makeSimple("int"), CppVariable("x")));
        auto p1 = makeCxParam(TypeKindVariable(makeSimple("char"), CppVariable("y")));
        auto f = CFunction(dummyUSR, CFunctionName("nothing"), [p0, p1],
                CxReturnType(makeSimple("int")), VariadicType.no, StorageClass.None);
        shouldEqual(format("%u", f), "int nothing(int x, char y); // None dummyUSR");
    }
}

@Name("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public));
    shouldEqual(m.isConst, false);
    shouldEqual(m.classification, MemberVirtualType.Normal);
    shouldEqual(m.name, "voider");
    shouldEqual(m.params_.length, 0);
    shouldEqual(m.returnType.toStringDecl("x"), "void x");
    shouldEqual(m.accessType, AccessType.Public);
}

@Name("Test creating a CppMethod with multiple parameters")
unittest {
    auto tk = makeSimple("char*");
    tk.attr.isPtr = Yes.isPtr;
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto m = CppMethod(dummyUSR, CppMethodName("none"), [p, p], CxReturnType(tk),
            CppAccess(AccessType.Public), CppConstMethod(true),
            CppVirtualMethod(MemberVirtualType.Virtual));

    shouldEqual(format("%u", m), "virtual char* none(char* x, char* x) const; // dummyUSR");
}

@Name("should represent the operator as a string")
unittest {
    auto m = CppMethodOp(dummyUSR, CppMethodName("operator="), CppAccess(AccessType.Public));

    shouldEqual(format("%u", m), "void operator=(); // dummyUSR");
}

@Name("should separate the operator keyword from the actual operator")
unittest {
    auto m = CppMethodOp(dummyUSR, CppMethodName("operator="), CppAccess(AccessType.Public));

    shouldEqual(m.op, "=");
}

@Name("should represent a class with one public method")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    shouldEqual(c.methods_pub.length, 1);
    shouldEqualPretty(format("%u", c), "class Foo { // Normal
public:
  void voider(); // dummyUSR
}; //Class:Foo");
}

@Name("should represent a class with one public operator overload")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto op = CppMethodOp(dummyUSR, CppMethodName("operator="), CppAccess(AccessType.Public));
    c.put(op);

    shouldEqualPretty(format("%u", c), "class Foo { // Normal
public:
  void operator=(); // dummyUSR
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
    auto stack = CppNsStack([CppNs("foo"), CppNs("bar")]);
    auto n = CppNamespace(stack);
    shouldEqual(cast(string) n.name, "bar");
    shouldEqual(n.isAnonymous, false);
}

@Name("Test of iterating over parameters in a class")
unittest {
    import std.array : appender;

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);

    auto app = appender!string();

    foreach (d; c.methodRange) {
        d.funcToString(app, "%u");
    }

    shouldEqual(app.data, "void voider(); // dummyUSR");
}

@Name("Test of toString for a free function")
unittest {
    auto ptk = makeSimple("char*");
    ptk.attr.isPtr = Yes.isPtr;
    auto rtk = makeSimple("int");
    auto f = CFunction(dummyUSR, CFunctionName("nothing"), [makeCxParam(TypeKindVariable(ptk,
            CppVariable("x"))), makeCxParam(TypeKindVariable(ptk, CppVariable("y")))],
            CxReturnType(rtk), VariadicType.no, StorageClass.None);

    shouldEqualPretty(format("%u", f), "int nothing(char* x, char* y); // None dummyUSR");
}

@Name("Test of Ctor's")
unittest {
    auto tk = makeSimple("char*");
    tk.attr.isPtr = Yes.isPtr;
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto ctor = CppCtor(dummyUSR, CppMethodName("ctor"), [p, p], CppAccess(AccessType.Public));

    shouldEqual(format("%u", ctor), "ctor(char* x, char* x); // dummyUSR");
}

@Name("Test of Dtor's")
unittest {
    auto dtor = CppDtor(dummyUSR, CppMethodName("~dtor"),
            CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual));

    shouldEqual(format("%u", dtor), "virtual ~dtor(); // dummyUSR");
}

@Name("Test of toString for CppClass")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public)));

    {
        auto m = CppCtor(dummyUSR, CppMethodName("Foo"), CxParam[].init,
                CppAccess(AccessType.Public));
        c.put(m);
    }

    {
        auto tk = makeSimple("int");
        auto m = CppMethod(dummyUSR, CppMethodName("fun"), CxReturnType(tk),
                CppAccess(AccessType.Protected), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Pure));
        c.put(m);
    }

    {
        auto tk = makeSimple("char*");
        tk.attr.isPtr = Yes.isPtr;
        auto m = CppMethod(dummyUSR, CppMethodName("gun"), CxReturnType(tk), CppAccess(AccessType.Private),
                CppConstMethod(false), CppVirtualMethod(MemberVirtualType.Normal));
        m.put(CxParam(TypeKindVariable(makeSimple("int"), CppVariable("x"))));
        m.put(CxParam(TypeKindVariable(makeSimple("int"), CppVariable("y"))));
        c.put(m);
    }

    {
        auto tk = makeSimple("int");
        auto m = CppMethod(dummyUSR, CppMethodName("wun"), CxReturnType(tk),
                CppAccess(AccessType.Public), CppConstMethod(true),
                CppVirtualMethod(MemberVirtualType.Normal));
        c.put(m);
    }

    shouldEqualPretty(format("%u", c), "class Foo { // Abstract
public:
  void voider(); // dummyUSR
  Foo(); // dummyUSR
  int wun() const; // dummyUSR
protected:
  virtual int fun() = 0; // dummyUSR
private:
  char* gun(int x, int y); // dummyUSR
}; //Class:Foo");
}

@Name("should be a class in a ns in the comment")
unittest {
    auto ns = CppNsStack([CppNs("a_ns"), CppNs("another_ns")]);
    auto c = CppClass(CppClassName("A_Class"), CppInherit[].init, ns);

    shouldEqualPretty(c.toString, "class A_Class { // Unknown
}; //Class:a_ns::another_ns::A_Class");
}

@Name("should contain the inherited classes")
unittest {
    CppInherit[] inherit;
    inherit ~= CppInherit(CppClassName("pub"), CppAccess(AccessType.Public));
    inherit ~= CppInherit(CppClassName("prot"), CppAccess(AccessType.Protected));
    inherit ~= CppInherit(CppClassName("priv"), CppAccess(AccessType.Private));

    auto c = CppClass(CppClassName("Foo"), inherit);

    shouldEqualPretty(c.toString,
            "class Foo : public pub, protected prot, private priv { // Unknown
}; //Class:Foo");
}

@Name("should contain nested classes")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    c.put(CppClass(CppClassName("Pub")), AccessType.Public);
    c.put(CppClass(CppClassName("Prot")), AccessType.Protected);
    c.put(CppClass(CppClassName("Priv")), AccessType.Private);

    shouldEqualPretty(c.toString, "class Foo { // Unknown
public:
class Pub { // Unknown
}; //Class:Pub
protected:
class Prot { // Unknown
}; //Class:Prot
private:
class Priv { // Unknown
}; //Class:Priv
}; //Class:Foo");
}

@Name("should be a virtual class")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppCtor(dummyUSR, CppMethodName("Foo"), CxParam[].init,
                CppAccess(AccessType.Public));
        c.put(m);
    }
    {
        auto m = CppDtor(dummyUSR, CppMethodName("~Foo"),
                CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }
    {
        auto m = CppMethod(dummyUSR, CppMethodName("wun"), CxReturnType(makeSimple("int")),
                CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }

    shouldEqualPretty(format("%u", c), "class Foo { // Virtual
public:
  Foo(); // dummyUSR
  virtual ~Foo(); // dummyUSR
  virtual int wun(); // dummyUSR
}; //Class:Foo");
}

@Name("should be a pure virtual class")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppCtor(dummyUSR, CppMethodName("Foo"), CxParam[].init,
                CppAccess(AccessType.Public));
        c.put(m);
    }
    {
        auto m = CppDtor(dummyUSR, CppMethodName("~Foo"),
                CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }
    {
        auto m = CppMethod(dummyUSR, CppMethodName("wun"), CxReturnType(makeSimple("int")),
                CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Pure));
        c.put(m);
    }

    shouldEqualPretty(format("%u", c), "class Foo { // Pure
public:
  Foo(); // dummyUSR
  virtual ~Foo(); // dummyUSR
  virtual int wun() = 0; // dummyUSR
}; //Class:Foo");
}

@Name("Test of toString for CppNamespace")
unittest {
    auto ns = CppNamespace.make(CppNs("simple"));

    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public)));
    ns.put(c);

    shouldEqualPretty(format("%u", ns), "namespace simple { //simple
class Foo { // Normal
public:
  void voider(); // dummyUSR
}; //Class:Foo
} //NS:simple");
}

@Name("Should show nesting of namespaces as valid C++ code")
unittest {
    auto stack = CppNsStack([CppNs("foo"), CppNs("bar")]);
    auto n = CppNamespace(stack);
    shouldEqualPretty(n.toString, "namespace bar { //foo::bar
} //NS:bar");
}

@Name("Test of toString for CppRoot")
unittest {
    auto root = CppRoot.make();

    { // free function
        auto f = CFunction(dummyUSR, CFunctionName("nothing"));
        root.put(f);
    }

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    root.put(c);

    root.put(CppNamespace.make(CppNs("simple")));

    shouldEqualPretty(format("%u", root), "void nothing(); // None dummyUSR
class Foo { // Normal
public:
  void voider(); // dummyUSR
}; //Class:Foo
namespace simple { //simple
} //NS:simple
");
}

@Name("CppNamespace.toString should return nested namespace")
unittest {
    auto stack = [CppNs("Depth1"), CppNs("Depth2"), CppNs("Depth3")];
    auto depth1 = CppNamespace(CppNsStack(stack[0 .. 1]));
    auto depth2 = CppNamespace(CppNsStack(stack[0 .. 2]));
    auto depth3 = CppNamespace(CppNsStack(stack[0 .. $]));

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
    auto f = CFunction(dummyUSR, CFunctionName("nothing"));
    n.put(f);

    shouldEqualPretty(format("%u", n), "namespace  { //
void nothing(); // None dummyUSR
} //NS:");
}

@Name("should be a hash value based on string representation")
unittest {
    struct A {
        mixin mixinUniqueId!size_t;
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
    auto v0 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    auto v1 = CxGlobalVariable(dummyUSR, makeSimple("int"), CppVariable("y"));

    shouldEqualPretty(format("%u", v0), "int x; // dummyUSR");
    shouldEqualPretty(format("%u", v1), "int y; // dummyUSR");
}

@Name("Should be globals stored in the root object")
unittest {
    auto v = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    auto n = CppNamespace.makeAnonymous();
    auto r = CppRoot.make();
    n.put(v);
    r.put(v);
    r.put(n);

    shouldEqualPretty(format("%u", r), "int x; // dummyUSR
namespace  { //
int x; // dummyUSR
} //NS:
");
}

@Name("should be possible to sort the data structures")
unittest {
    import std.array : array;

    auto v0 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    auto v1 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    auto r = CppRoot.make();
    r.put(v0);
    r.put(v1);
    r.put(v0);

    auto s = r.globalRange;
    shouldEqual(s.array().length, 1);
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

    shouldEqualPretty(c.toString, "class A : public ns1::Class { // Unknown
}; //Class:A");
}

@Name("Should be a class with a data member")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto tk = makeSimple("int");
    c.put(TypeKindVariable(tk, CppVariable("x")), AccessType.Public);

    shouldEqualPretty(c.toString, "class Foo { // Unknown
public:
  int x;
}; //Class:Foo");
}

@Name("Should be an abstract class")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppDtor(dummyUSR, CppMethodName("~Foo"),
                CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Normal));
        c.put(m);
    }
    {
        auto m = CppMethod(dummyUSR, CppMethodName("wun"), CppAccess(AccessType.Public),
                CppConstMethod(false), CppVirtualMethod(MemberVirtualType.Pure));
        c.put(m);
    }
    {
        auto m = CppMethod(dummyUSR, CppMethodName("gun"), CppAccess(AccessType.Public),
                CppConstMethod(false), CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }

    // 43 is derived from makeUniqueUSR
    shouldEqualPretty(format("%u", c), "class Foo { // Abstract
public:
  ~Foo(); // dummyUSR
  virtual void wun() = 0; // dummyUSR
  virtual void gun(); // dummyUSR
}; //Class:Foo");

}

@Name("Should be a class with comments")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    c.put("A comment");

    shouldEqualPretty(c.toString, "// A comment
class Foo { // Unknown
}; //Class:Foo");
}
