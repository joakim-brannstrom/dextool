// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Structuraly represents the semantic-centric view of of C/C++ code.

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
import std.typecons : Typedef, Tuple, Flag, Yes, No;
import std.variant : Algebraic;
import logger = std.experimental.logger;

public import cpptooling.data.type;

import cpptooling.analyzer.type;
import cpptooling.data.symbol.types : USRType;
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

string funcToString(CppClass.CppFunc func) @trusted {
    import std.variant : visit;

    //dfmt off
    return func.visit!((CppMethod a) => a.toString,
                       (CppMethodOp a) => a.toString,
                       (CppCtor a) => a.toString,
                       (CppDtor a) => a.toString);
    //dfmt on
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

/// Expects a toString function where it is mixed in.
/// base value for hash is 0 to force deterministic hashes. Use the pointer for
/// unique between objects.
private template mixinUniqueId() {
    //TODO add check to see that this do NOT already have id_.

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

    size_t id() const {
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

    auto kind() const {
        return kind_;
    }
}

///TODO change to a algebraic with two kinds, Location and None.
pure @safe nothrow struct CxLocation {
    string file;
    uint line;
    uint column;

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

    auto location() const {
        return loc_;
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
        (TypeKindVariable tk) {return tk.type.toStringDecl(tk.name.str);},
        (TypeKindAttr t) { return t.toStringDecl; },
        (VariadicType a) { return "..."; }
        );
    // dfmt on
}

/// Convert a TypeKindVariable to a string.
string toInternal(TypeKindVariable tk) @trusted {
    return tk.type.toStringDecl(tk.name.str);
}

/// Join a range of CxParams to a string separated by ", ".
string joinParams(const(CxParam)[] r) @safe {
    import std.algorithm : joiner, map;
    import std.conv : text;
    import std.range : enumerate;

    static string getTypeName(T : const(Tx), Tx)(T p, ulong uid) @trusted {
        import std.variant : visit;

        // dfmt off
        auto x = (cast(Tx) p).visit!(
            (TypeKindVariable tk) {return tk.type.toStringDecl(tk.name.str);},
            (TypeKindAttr t) { return t.toStringDecl("x" ~ text(uid)); },
            (VariadicType a) { return "..."; }
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

    static string getName(T : const(Tx), Tx)(T p, ulong uid) @trusted {
        import std.variant : visit;

        // dfmt off
        return (cast(Tx) p).visit!(
            (TypeKindVariable tk) {return tk.name.str;},
            (TypeKindAttr t) { return "x" ~ text(uid); },
            (VariadicType a) { return ""; }
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

private void assertVisit(T : const(Tx), Tx)(ref T p) @trusted {
    import std.variant : visit;

    // dfmt off
    (cast(Tx) p).visit!(
        (TypeKindVariable tk) { assert(tk.name.length > 0);
                                assert(tk.type.toStringDecl.length > 0);},
        (TypeKindAttr t)      { assert(t.toStringDecl.length > 0); },
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

    this(TypeKindAttr type, CppVariable name, CxLocation loc) {
        this(TypeKindVariable(type, name), loc);
    }

const:

    string toString()
    in {
        import std.algorithm : among;

        // see switch stmt for explanation.
        assert(!variable.type.kind.info.kind.among(TypeKind.Info.Kind.ctor,
                TypeKind.Info.Kind.dtor));
    }
    body {
        import std.array : Appender, appender;
        import std.ascii : newline;
        import std.format : formattedWrite;
        import cpptooling.analyzer.type : TypeKind;

        auto app = appender!string();
        final switch (variable.type.kind.info.kind) with (TypeKind.Info) {
        case Kind.record:
        case Kind.func:
        case Kind.funcPtr:
        case Kind.simple:
        case Kind.typeRef:
        case Kind.array:
        case Kind.pointer:
            app.put(variable.type.toStringDecl(variable.name.str));
            break;
        case Kind.ctor:
            logger.error("Assumption broken. A global variable with the type of a Constructor");
            break;
        case Kind.dtor:
            logger.error("Assumption broken. A global variable with the type of a Destructor");
            break;
        case Kind.null_:
            logger.error("Type of global variable is null. Identifier ",
                    variable.name.str);
            break;
        }
        formattedWrite(app, "; // %s", location());

        return app.data;
    }

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

            auto accessType() {
                return accessType_;
            }

            auto name() {
                return name_;
            }
        }

        private MemberVirtualType classification_;
        private CppAccess accessType_;
        private CppMethodName name_;
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
pure @safe nothrow struct CFunction {
    import std.typecons : TypedefType;

    private {
        bool isInitialized;
        CFunctionName name_;
        CxParam[] params;
        CxReturnType returnType_;
        VariadicType isVariadic_;
        StorageClass storageClass_;
    }

    mixin mixinUniqueId;
    mixin mixinSourceLocation;

    /// C function representation.
    this(const CFunctionName name, const CxParam[] params_, const CxReturnType return_type,
            const VariadicType is_variadic, const StorageClass storage_class, const CxLocation loc) {
        this.name_ = name;
        this.returnType_ = return_type;
        this.isVariadic_ = is_variadic;
        this.storageClass_ = storage_class;

        this.params = params_.dup;

        setLocation(loc);
        setUniqueId(internalToString);

        isInitialized = true;
    }

    /// Function with no parameters.
    this(const CFunctionName name, const CxReturnType return_type, const CxLocation loc) {
        this(name, CxParam[].init, return_type, VariadicType.no, StorageClass.None, loc);
    }

    /// Function with no parameters and returning void.
    this(const CFunctionName name, const CxLocation loc) {
        CxReturnType void_ = makeSimple("void");
        this(name, CxParam[].init, void_, VariadicType.no, StorageClass.None, loc);
    }

const:

    /// A range over the parameters of the function.
    auto paramRange() @nogc @safe pure nothrow {
        return params;
    }

    @nogc {
        auto returnType() {
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

    // Separating file location from the rest
    private string internalToString() {
        import std.array : Appender, appender;
        import std.format : formattedWrite;

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s);", returnType.toStringDecl, name.str,
                paramRange.joinParams);
        return rval.data;
    }

    string toString() {
        import std.array : Appender, appender;
        import std.conv : to;
        import std.format : formattedWrite;

        auto rval = appender!string();
        formattedWrite(rval, "%s // %s %s", internalToString(),
                to!string(storageClass), location());

        return rval.data;
    }

    invariant() {
        if (isInitialized) {
            assert(name_.length > 0);
            assert(returnType_.toStringDecl.length > 0);

            foreach (p; params) {
                assertVisit(p);
            }
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

    mixin mixinUniqueId;

    @disable this();

    this(const CppMethodName name, const CxParam[] params, const CppAccess access) {
        this.name_ = name;
        this.accessType_ = access;
        this.params_ = params.dup;

        setUniqueId(toString);
    }

    mixin CppMethodGeneric.Parameters;

const:

    string toString() {
        import std.format : format;

        return format("%s(%s)", name_.str, paramRange.joinParams);
    }

    auto accessType() {
        return accessType_;
    }

    auto name() {
        return name_;
    }

    invariant() {
        assert(name_.length > 0);

        foreach (p; params_) {
            assertVisit(p);
        }
    }
}

pure @safe nothrow struct CppDtor {
    mixin mixinUniqueId;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.StringHelperVirtual;

    @disable this();

    this(const CppMethodName name, const CppAccess access, const CppVirtualMethod virtual) {
        import std.typecons : TypedefType;

        this.classification_ = cast(TypedefType!CppVirtualMethod) virtual;
        this.accessType_ = access;
        this.name_ = name;

        setUniqueId(name_.str);
    }

const:

    string toString() {
        import std.algorithm : joiner;
        import std.range : only;
        import std.conv : text;

        // dfmt off
        return
            only(
                 helperVirtualPre(classification_),
                 name_.str,
                 "()"
                )
            .joiner()
            .text;
        // dfmt on
    }

    invariant() {
        assert(name_.length > 0);
        assert(classification_ != MemberVirtualType.Unknown);
    }
}

pure @safe nothrow struct CppMethod {
    mixin mixinUniqueId;
    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.MethodProperties;

    @disable this();

    this(const CppMethodName name, const CxParam[] params, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        import std.typecons : TypedefType;

        this.classification_ = cast(TypedefType!CppVirtualMethod) virtual;
        this.accessType_ = access;
        this.name_ = name;
        this.returnType_ = return_type;
        this.isConst_ = cast(TypedefType!CppConstMethod) const_;

        this.params_ = params.dup;

        setUniqueId(signatureToString);
    }

    /// Function with no parameters.
    this(const CppMethodName name, const CxReturnType return_type, const CppAccess access,
            const CppConstMethod const_, const CppVirtualMethod virtual) {
        this(name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(const CppMethodName name, const CppAccess access, const CppConstMethod const_ = false,
            const CppVirtualMethod virtual = MemberVirtualType.Normal) {
        CxReturnType void_ = makeSimple("void");
        this(name, CxParam[].init, void_, access, const_, virtual);
    }

const:

    /// Signature of the method.
    private string signatureToString() {
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only;

        // dfmt off
        return
            only(
                 name_.str,
                 format("(%s)", paramRange.joinParams),
                 helperConst(isConst)
                )
            .joiner()
            .text;
        // dfmt on
    }

    string toString() {
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only;

        // dfmt off
        return
            only(
                 helperVirtualPre(classification_),
                 returnType_.toStringDecl,
                 " ",
                 signatureToString,
                 helperVirtualPost(classification_)
                )
            .joiner()
            .text;
        // dfmt on
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.toStringDecl.length > 0);
        assert(classification_ != MemberVirtualType.Unknown);

        foreach (p; params_) {
            assertVisit(p);
        }
    }
}

pure @safe nothrow struct CppMethodOp {
    mixin mixinUniqueId;
    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.MethodProperties;

    @disable this();

    this(const CppMethodName name, const CxParam[] params, const CxReturnType return_type,
            const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        import std.typecons : TypedefType;

        this.classification_ = cast(TypedefType!CppVirtualMethod) virtual;
        this.accessType_ = access;
        this.name_ = name;
        this.isConst_ = cast(TypedefType!CppConstMethod) const_;
        this.returnType_ = return_type;

        this.params_ = params.dup;
    }

    /// Operator with no parameters.
    this(const CppMethodName name, const CxReturnType return_type, const CppAccess access,
            const CppConstMethod const_, const CppVirtualMethod virtual) {
        this(name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Operator with no parameters and returning void.
    this(const CppMethodName name, const CppAccess access, const CppConstMethod const_ = false,
            const CppVirtualMethod virtual = MemberVirtualType.Normal) {
        CxReturnType void_ = makeSimple("void");
        this(name, CxParam[].init, void_, access, const_, virtual);
    }

const:

    /// Signature of the method.
    private string signatureToString() {
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only;

        // dfmt off
        return
            only(
                 name_.str,
                 format("(%s)", paramRange.joinParams),
                 helperConst(isConst),
                )
            .joiner()
            .text;
        // dfmt on
    }

    string toString() {
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only;

        // dfmt off
        return
            only(
                 helperVirtualPre(classification_),
                 returnType_.toStringDecl,
                 " ",
                 signatureToString,
                 helperVirtualPost(classification_),
                 // distinguish an operator from a normal method
                 " /* operator */"
                )
            .joiner()
            .text;
        // dfmt on
    }

    /// The operator type, aka in C++ the part after "operator"
    auto op()
    in {
        assert(name_.length > 8);
    }
    body {
        return CppMethodName((cast(string) name_)[8 .. $]);
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.toStringDecl.length > 0);
        assert(classification_ != MemberVirtualType.Unknown);

        foreach (p; params_) {
            assertVisit(p);
        }
    }
}

pure @safe nothrow struct CppInherit {
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    USRType usr;

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
        return ns;
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

    auto name() {
        return this.name_;
    }

    auto access() {
        return access_;
    }

    FullyQualifiedNameType fullyQualifiedName() {
        //TODO optimize by only calculating once.
        import std.algorithm : map, joiner;
        import std.range : chain, only;
        import std.conv : text;

        // dfmt off
            auto r = chain(ns.map!(a => cast(string) a),
                           only(cast(string) name_))
                .joiner("::")
                .text();
            return FullyQualifiedNameType(r);
            // dfmt on
    }
}

pure @safe nothrow struct CppClass {
    import std.variant : Algebraic, visit;
    import std.typecons : TypedefType;
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    alias CppFunc = Algebraic!(CppMethod, CppMethodOp, CppCtor, CppDtor);

    USRType usr;

    private {
        CppClassName name_;
        CppInherit[] inherits_;
        CppNsStack reside_in_ns;

        ClassVirtualType classification_;

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

        classification_ = classifyClass(classification_, f,
                cast(Flag!"hasMember")(memberRange.length > 0));
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

        return reside_in_ns.retro;
    }

    auto commentRange() @nogc {
        return comments;
    }

const:

    string toString() {
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
                  only(" { //", to!string(classification_), location.toString).joiner(" ")
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
                  comments.map!(a => format("// %s", a)).joiner(newline),
                  begin_class, newline, // <- not a typo, easier to see newline
                  // methods
                  methods_pub.takeOne.map!(a => "public:" ~ newline).joiner(),
                  methods_pub.map!(a => "  " ~ a.funcToString).roundRobin((";" ~ newline).repeat.take(methods_pub.length)).joiner(),
                  methods_prot.takeOne.map!(a => "protected:" ~ newline).joiner(),
                  methods_prot.map!(a => "  " ~ a.funcToString).roundRobin((";" ~ newline).repeat.take(methods_prot.length)).joiner(),
                  methods_priv.takeOne.map!(a => "private:" ~ newline).joiner(),
                  methods_priv.map!(a => "  " ~ a.funcToString).roundRobin((";" ~ newline).repeat.take(methods_priv.length)).joiner(),
                  // classes
                  classes_pub.takeOne.map!(a => "public:" ~ newline).joiner(),
                  classes_pub.map!(a => a.toString).roundRobin(newline.repeat.take(classes_pub.length)).joiner(),
                  classes_prot.takeOne.map!(a => "protected:" ~ newline).joiner(),
                  classes_prot.map!(a => a.toString).roundRobin(newline.repeat.take(classes_prot.length)).joiner(),
                  classes_priv.takeOne.map!(a => "private:" ~ newline).joiner(),
                  classes_priv.map!(a => a.toString).roundRobin(newline.repeat.take(classes_priv.length)).joiner(),
                  members_pub.map!(a => "  " ~ toInternal(a) ~ ";" ~ newline).joiner(),
                  members_prot.map!(a => "  " ~ toInternal(a) ~ ";" ~ newline).joiner(),
                  members_priv.map!(a => "  " ~ toInternal(a) ~ ";" ~ newline).joiner(),
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

    bool isVirtual() {
        import std.algorithm : among;

        with (ClassVirtualType) {
            return classification_.among(Virtual, VirtualDtor, Abstract, Pure) != 0;
        }
    }

    bool isAbstract() {
        with (ClassVirtualType) {
            return classification_ == Abstract;
        }
    }

    bool isPure() {
        import std.algorithm : among;

        with (ClassVirtualType) {
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
                         reside_in_ns.map!(a => cast(string) a).joiner("::"),
                         reside_in_ns.takeOne.map!(a => "::").joiner(),
                         only(name_.str).joiner()
                        );
        return FullyQualifiedNameType(fqn.array().toUTF8);
        // dfmt on
    }
}

// Clang have no property that clasifies a class as virtual/abstract/pure.
private ClassVirtualType classifyClass(T)(in ClassVirtualType current, T p,
        Flag!"hasMember" hasMember) @safe {
    import std.algorithm : among;

    struct Rval {
        enum Type {
            Method,
            Ctor,
            Dtor
        }

        MemberVirtualType value;
        Type t;
    }

    static Rval getMethodClassification(T func) @trusted
    out (result) {
        assert(result.value != MemberVirtualType.Unknown);
    }
    body {
        import std.variant : visit;

        //dfmt off
        return func.visit!((CppMethod a) => Rval(a.classification(), Rval.Type.Method),
                           (CppMethodOp a) => Rval(a.classification(), Rval.Type.Method),
                           (CppCtor a) => Rval(MemberVirtualType.Normal, Rval.Type.Ctor),
                           (CppDtor a) => Rval(a.classification(), Rval.Type.Dtor));
        //dfmt on
    }

    ClassVirtualType r = current;
    auto mVirt = getMethodClassification(p);

    final switch (current) {
    case ClassVirtualType.Pure:
        // a pure interface can't have members
        if (hasMember) {
            r = ClassVirtualType.Abstract;
        }  // a non-virtual destructor lowers purity
        else if (mVirt.t == Rval.Type.Dtor && mVirt.value == MemberVirtualType.Normal) {
            r = ClassVirtualType.Abstract;
        } else if (mVirt.t == Rval.Type.Method && mVirt.value == MemberVirtualType.Virtual) {
            r = ClassVirtualType.Abstract;
        }
        break;
    case ClassVirtualType.Abstract:
        // one or more methods are pure, stay at this state
        break;
    case ClassVirtualType.Virtual:
        if (mVirt.value == MemberVirtualType.Pure) {
            r = ClassVirtualType.Abstract;
        }
        break;
    case ClassVirtualType.VirtualDtor:
        if (mVirt.value == MemberVirtualType.Pure) {
            r = ClassVirtualType.Pure;
        } else {
            r = ClassVirtualType.Virtual;
        }
        break;
    case ClassVirtualType.Normal:
        if (mVirt.t.among(Rval.Type.Method,
                Rval.Type.Dtor) && mVirt.value == MemberVirtualType.Pure) {
            r = ClassVirtualType.Abstract;
        } else if (mVirt.t.among(Rval.Type.Method, Rval.Type.Dtor)
                && mVirt.value == MemberVirtualType.Virtual) {
            r = ClassVirtualType.Virtual;
        }
        break;
    case ClassVirtualType.Unknown:
        // ctor cannot affect purity evaluation
        if (mVirt.t == Rval.Type.Dtor
                && mVirt.value.among(MemberVirtualType.Pure, MemberVirtualType.Virtual)) {
            r = ClassVirtualType.VirtualDtor;
        } else if (mVirt.t != Rval.Type.Ctor) {
            final switch (mVirt.value) {
            case MemberVirtualType.Unknown:
                r = ClassVirtualType.Unknown;
                break;
            case MemberVirtualType.Normal:
                r = ClassVirtualType.Normal;
                break;
            case MemberVirtualType.Virtual:
                r = ClassVirtualType.Virtual;
                break;
            case MemberVirtualType.Pure:
                r = ClassVirtualType.Pure;
                break;
            }
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
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    private {
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

        return stack.retro;
    }

    auto classRange() @nogc {
        return classes;
    }

    auto funcRange() @nogc {
        return funcs;
    }

    auto namespaceRange() @nogc {
        return namespaces;
    }

    auto globalRange() @nogc {
        return globals;
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

    auto isAnonymous() {
        return name_.length == 0;
    }

    auto name() {
        return name_;
    }

    auto resideInNs() {
        //TODO change name, it is the full stack. So fully qualified name.
        return stack;
    }

    auto fullyQualifiedName() {
        //TODO optimize by only calculating once.

        import std.array : array;
        import std.algorithm : map, joiner;
        import std.range : takeOne, only, chain, takeOne;
        import std.utf : byChar, toUTF8;

        // dfmt off
            auto fqn = stack.map!(a => cast(string) a).joiner("::");
            return FullyQualifiedNameType(fqn.array().toUTF8);
            // dfmt on
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
        return ns;
    }

    auto classRange() @nogc {
        return classes;
    }

    auto funcRange() @nogc {
        return funcs;
    }

    auto globalRange() @nogc {
        return globals;
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

@Name("Test of c-function")
unittest {
    { // simple version, no return or parameters.
        auto f = CFunction(CFunctionName("nothing"), dummyLoc);
        shouldEqual(f.returnType.toStringDecl("x"), "void x");
        shouldEqual(f.toString, "void nothing(); // None File:a.h Line:123 Column:45");
    }

    { // extern storage.
        auto f = CFunction(CFunctionName("nothing"), [], CxReturnType(makeSimple("void")), VariadicType.no, StorageClass.Extern, dummyLoc);
        shouldEqual(f.returnType.toStringDecl("x"), "void x");
        shouldEqual(f.toString, "void nothing(); // Extern File:a.h Line:123 Column:45");
    }

    { // a return type.
        auto f = CFunction(CFunctionName("nothing"), CxReturnType(makeSimple("int")), dummyLoc);
        shouldEqual(f.toString, "int nothing(); // None File:a.h Line:123 Column:45");
    }

    { // return type and parameters.
        auto p0 = makeCxParam(TypeKindVariable(makeSimple("int"), CppVariable("x")));
        auto p1 = makeCxParam(TypeKindVariable(makeSimple("char"), CppVariable("y")));
        auto f = CFunction(CFunctionName("nothing"), [p0, p1],
            CxReturnType(makeSimple("int")), VariadicType.no, StorageClass.None, dummyLoc);
        shouldEqual(f.toString, "int nothing(int x, char y); // None File:a.h Line:123 Column:45");
    }
}

@Name("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
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

    auto m = CppMethod(CppMethodName("none"), [p, p], CxReturnType(tk),
        CppAccess(AccessType.Public), CppConstMethod(true), CppVirtualMethod(MemberVirtualType.Virtual));

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
    shouldEqualPretty(c.toString, "class Foo { // Normal File:noloc Line:0 Column:0
public:
  void voider();
}; //Class:Foo");
}

@Name("should represent a class with one public oeprator overload")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto op = CppMethodOp(CppMethodName("operator="), CppAccess(AccessType.Public));
    c.put(op);

    shouldEqualPretty(c.toString, "class Foo { // Normal File:noloc Line:0 Column:0
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
    auto ptk = makeSimple("char*");
    ptk.attr.isPtr = Yes.isPtr;
    auto rtk = makeSimple("int");
    auto f = CFunction(CFunctionName("nothing"),
        [makeCxParam(TypeKindVariable(ptk, CppVariable("x"))),
        makeCxParam(TypeKindVariable(ptk, CppVariable("y")))],
        CxReturnType(rtk), VariadicType.no, StorageClass.None, dummyLoc);

    shouldEqualPretty(f.toString, "int nothing(char* x, char* y); // None File:a.h Line:123 Column:45");
}

@Name("Test of Ctor's")
unittest {
    auto tk = makeSimple("char*");
    tk.attr.isPtr = Yes.isPtr;
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto ctor = CppCtor(CppMethodName("ctor"), [p, p], CppAccess(AccessType.Public));

    shouldEqual(ctor.toString, "ctor(char* x, char* x)");
}

@Name("Test of Dtor's")
unittest {
    auto dtor = CppDtor(CppMethodName("~dtor"), CppAccess(AccessType.Public),
        CppVirtualMethod(MemberVirtualType.Virtual));

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
        auto tk = makeSimple("int");
        auto m = CppMethod(CppMethodName("fun"), CxReturnType(tk),
            CppAccess(AccessType.Protected), CppConstMethod(false),
            CppVirtualMethod(MemberVirtualType.Pure));
        c.put(m);
    }

    {
        auto tk = makeSimple("char*");
        tk.attr.isPtr = Yes.isPtr;
        auto m = CppMethod(CppMethodName("gun"),
            CxReturnType(tk),
            CppAccess(AccessType.Private), CppConstMethod(false),
            CppVirtualMethod(MemberVirtualType.Normal));
        m.put(CxParam(TypeKindVariable(makeSimple("int"), CppVariable("x"))));
        m.put(CxParam(TypeKindVariable(makeSimple("int"), CppVariable("y"))));
        c.put(m);
    }

    {
        auto tk = makeSimple("int");
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(tk),
            CppAccess(AccessType.Public), CppConstMethod(true), CppVirtualMethod(MemberVirtualType.Normal));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // Abstract File:noloc Line:0 Column:0
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
                      "class A_Class { // Unknown File:a.h Line:123 Column:45
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
        "class Foo : public pub, protected prot, private priv { // Unknown File:a.h Line:123 Column:45
}; //Class:Foo");
}

@Name("should contain nested classes")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    c.put(CppClass(CppClassName("Pub")), AccessType.Public);
    c.put(CppClass(CppClassName("Prot")), AccessType.Protected);
    c.put(CppClass(CppClassName("Priv")), AccessType.Private);

    shouldEqualPretty(c.toString, "class Foo { // Unknown File:noloc Line:0 Column:0
public:
class Pub { // Unknown File:noloc Line:0 Column:0
}; //Class:Pub
protected:
class Prot { // Unknown File:noloc Line:0 Column:0
}; //Class:Prot
private:
class Priv { // Unknown File:noloc Line:0 Column:0
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
            CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeSimple("int")),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // Virtual File:noloc Line:0 Column:0
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
            CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeSimple("int")),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(MemberVirtualType.Pure));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // Pure File:noloc Line:0 Column:0
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
class Foo { // Normal File:noloc Line:0 Column:0
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

void nothing(); // None File:a.h Line:123 Column:45

class Foo { // Normal File:noloc Line:0 Column:0
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
void nothing(); // None File:a.h Line:123 Column:45
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
    auto v0 = CxGlobalVariable(TypeKindVariable(makeSimple("int"), CppVariable("x")), dummyLoc);
    auto v1 = CxGlobalVariable(makeSimple("int"), CppVariable("y"),
        dummyLoc);

    shouldEqualPretty(v0.toString, "int x; // File:a.h Line:123 Column:45");
    shouldEqualPretty(v1.toString, "int y; // File:a.h Line:123 Column:45");
}

@Name("globals in root")
unittest {
    auto v = CxGlobalVariable(TypeKindVariable(makeSimple("int"), CppVariable("x")), dummyLoc);
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
    auto v0 = CxGlobalVariable(TypeKindVariable(makeSimple("int"), CppVariable("x")), dummyLoc);
    auto v1 = CxGlobalVariable(TypeKindVariable(makeSimple("int"), CppVariable("x")), dummyLoc2);
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
        "class A : public ns1::Class { // Unknown File:noloc Line:0 Column:0
}; //Class:A");
}

@Name("Should be a class with a data member")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto tk = makeSimple("int");
    c.put(TypeKindVariable(tk, CppVariable("x")), AccessType.Public);

    shouldEqualPretty(c.toString, "class Foo { // Unknown File:noloc Line:0 Column:0
  int x;
}; //Class:Foo");
}

@Name("Should be an abstract class")
unittest {
    logger.trace("aaaaaaaaaaaaaaaaaaaa");
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppDtor(CppMethodName("~Foo"), CppAccess(AccessType.Public),
            CppVirtualMethod(MemberVirtualType.Normal));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("wun"),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(MemberVirtualType.Pure));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("gun"),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // Abstract File:noloc Line:0 Column:0
public:
  ~Foo();
  virtual void wun() = 0;
  virtual void gun();
}; //Class:Foo");

}
