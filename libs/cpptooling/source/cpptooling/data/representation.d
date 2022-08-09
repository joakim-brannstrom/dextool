/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Structuraly represents the semantic-centric view of of C/C++ code.

The guiding principle for this module is: "Correct by construction".
 * After the data is created it should be "correct".
 * As far as possible avoid runtime errors.

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

import logger = std.experimental.logger;
import std.algorithm : joiner, map, filter, makeIndex;
import std.array : Appender, array;
import std.format : format, FormatSpec;
import std.range : isInputRange;
import std.traits : Unqual;
import std.typecons : Tuple, Flag, Yes, No, Nullable;

public import cpptooling.data.type;

import my.sumtype;

import cpptooling.data.kind_type;
import cpptooling.data.symbol.types : USRType;

static import cpptooling.data.class_classification;

version (unittest) {
    import unit_threaded : Name;
    import unit_threaded : shouldBeTrue, shouldEqual, shouldBeGreaterThan;
    import unit_threaded : writelnUt;

    private enum dummyUSR = USRType("dummyUSR");
}

/// Generate the next globally unique ID.
size_t nextUniqueID() @safe nothrow {
    import cpptooling.utility.global_unique : nextNumber;

    return nextNumber;
}

/** Construct a USR that is ensured to be unique.
 *
 * The USR start with a number which is an illegal symbol in C/C++.
 * Which should result in them never clashing with those from sources derived
 * from source code.
 */
USRType makeUniqueUSR() @safe nothrow {
    import std.conv : text;

    return USRType(text(nextUniqueID));
}

void funcToString(Writer, Char)(CppClass.CppFunc func, scope Writer w, in Char[] fmt) @trusted {
    import std.format : formattedWrite;

    //dfmt off
    func.match!((CppMethod a) => formattedWrite(w, fmt, a),
                (CppMethodOp a) => formattedWrite(w, fmt, a),
                (CppCtor a) => formattedWrite(w, fmt, a),
                (CppDtor a) => formattedWrite(w, fmt, a));
    //dfmt on
}

string funcToString(CppClass.CppFunc func) @safe {
    import std.exception : assumeUnique;

    char[] buf;
    buf.reserve(100);
    funcToString(func, (const(char)[] s) { buf ~= s; }, "%s");
    auto trustedUnique(T)(T t) @trusted {
        return assumeUnique(t);
    }

    return trustedUnique(buf);
}

string methodNameToString(CppClass.CppFunc func) @trusted {
    //dfmt off
    return func.match!((CppMethod a) => a.name,
                       (CppMethodOp a) => a.name,
                       (CppCtor a) => a.name.get,
                       (CppDtor a) => a.name);
    //dfmt on
}

/// Convert a CxParam to a string.
string paramTypeToString(CxParam p, string id = "") @trusted {
    // dfmt off
    return p.match!(
        (TypeKindVariable tk) { return tk.type.toStringDecl(id); },
        (TypeKindAttr t) { return t.toStringDecl; },
        (VariadicType a) { return "..."; }
        );
    // dfmt on
}

/// Convert a CxParam to a string.
string paramNameToString(CxParam p, string id = "") @trusted {
    // dfmt off
    return p.match!(
        (TypeKindVariable tk) { return tk.name; },
        (TypeKindAttr t) { return id; },
        (VariadicType a) { return "..."; }
        );
    // dfmt on
}

/// Standard implementation of toString using the toString that take an
/// OutputRange.
private string standardToString() {
    return q{
    string toString()() {
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

/// Expects a toString function where it is mixed in.
/// base value for hash is 0 to force deterministic hashes. Use the pointer for
/// unique between objects.
private template mixinUniqueId(IDType) if (is(IDType == size_t) || is(IDType == string)) {
    //TODO add check to see that this do NOT already have id_.

    private IDType id_;

@safe:

    static if (is(IDType == size_t)) {
        private void setUniqueId(string identifier) @safe pure nothrow {
            import my.hash : makeCrc64Iso;

            this.id_ = makeCrc64Iso(cast(const(ubyte)[]) identifier).c0;
        }
    } else static if (is(IDType == string)) {
        private void setUniqueId(Char)(Char[] identifier) @safe pure nothrow {
            this.id_ = identifier.idup;
        }
    } else {
        static assert(false, "IDType must be either size_t or string");
    }

    IDType id() @safe pure const nothrow {
        return id_;
    }

    int opCmp(T : typeof(this))(auto ref const T rhs) const {
        return this.id_ < rhs.id_;
    }

    bool opEquals(T : typeof(this))(auto ref const T rhs) const {
        return this.id_ == rhs.id_;
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        return id_.hashOf;
    }

    void unsafeForceID(IDType id) {
        this.id_ = id;
    }
}

private template mixinCommentHelper() {
    private string[] comments_;

    /** Add a comment.
     *
     * Params:
     *  txt = a oneline comment, must NOT end with newline
     */
    auto ref comment(string txt) @safe pure nothrow {
        comments_ ~= txt;
        return this;
    }

    string[] comments() @safe pure nothrow @nogc {
        return comments_;
    }

    private void helperPutComments(Writer)(scope Writer w) const {
        import std.ascii : newline;
        import std.range.primitives : put;

        foreach (l; comments_) {
            put(w, "// ");
            put(w, l);
            put(w, newline);
        }
    }
}

/// Convert a CxParam to a string.
string toInternal(CxParam p) @trusted {
    // dfmt off
    return p.match!(
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
string joinParams(CxParam[] r) @safe {
    import std.conv : text;
    import std.range : enumerate;

    static string getTypeName(CxParam p, ulong uid) @trusted {
        // dfmt off
        auto x = p.match!(
            (TypeKindVariable t) {return t.type.toStringDecl(t.name);},
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

    static string getName(CxParam p, ulong uid) @trusted {
        // dfmt off
        return p.match!(
            (TypeKindVariable tk) {return tk.name;},
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

/// Join a range of CxParams to a string of the parameter types separated by ", ".
string joinParamTypes(CxParam[] r) @safe {
    import std.algorithm : joiner, map;
    import std.conv : text;
    import std.range : enumerate;

    // dfmt off
    return r
        .enumerate
        .map!(a => getType(a.value))
        .joiner(", ")
        .text();
    // dfmt on
}

/// Get the name of a C++ method.
string getName()(ref CppClass.CppFunc method) @trusted {
    // dfmt off
    return method.match!(
                         (CppMethod m) => m.name,
                         (CppMethodOp m) => "",
                         (CppCtor m) => m.name.get,
                         (CppDtor m) => m.name);
    // dfmt on
}

/// Get the name of a parameter or the default.
string getName(CxParam p, string default_) @safe {
    static string getName(CxParam p, string default_) @trusted {
        // dfmt off
        return p.match!(
            (TypeKindVariable tk) {return tk.name;},
            (TypeKindAttr t) { return default_; },
            (VariadicType a) { return default_; }
            );
        // dfmt on
    }

    return getName(p, default_);
}

/// Get the parameter type as a string.
string getType(CxParam p) @trusted {
    return p.match!((TypeKindVariable t) { return t.type.toStringDecl; }, (TypeKindAttr t) {
        return t.toStringDecl;
    }, (VariadicType a) { return "..."; });
}

/// Make a variadic parameter.
CxParam makeCxParam() @trusted {
    return CxParam(VariadicType.yes);
}

/// CxParam created by analyzing a TypeKindVariable.
/// A empty variable name means it is of the algebraic type TypeKind.
CxParam makeCxParam(TypeKindVariable tk) @trusted {
    if (tk.name.length == 0)
        return CxParam(tk.type);
    return CxParam(tk);
}

struct UnpackParamResult {
    TypeKindAttr type;
    bool isVariadic;
}

/// Unpack a CxParam.
UnpackParamResult unpackParam(CxParam p) @safe {
    UnpackParamResult rval;

    // dfmt off
    () @trusted {
        p.match!((TypeKindVariable v) => rval.type = v.type,
                 (TypeKindAttr v) => rval.type = v,
                 (VariadicType v) { rval.isVariadic = true; return rval.type; });
    }();
    // dfmt on

    return rval;
}

private void assertVisit(const CxParam p) @trusted {
    // dfmt off
    p.match!(
        (const TypeKindVariable v) { assert(v.name.length > 0);
                                     assert(v.type.toStringDecl.length > 0);},
        (const TypeKindAttr v)     { assert(v.toStringDecl.length > 0); },
        (const VariadicType v)     {});
    // dfmt on
}

struct CxGlobalVariable {
    mixin mixinUniqueId!size_t;

    private TypeKindVariable variable;

    Nullable!USRType usr;
    Nullable!Language language;

    invariant {
        assert(usr.isNull || usr.get.length > 0);
    }

    /**
     * do NOT use the usr from var.type.kind.usr, it is for the type not the
     * instance.
     */
    this(USRType usr, TypeKindVariable var) @safe pure nothrow {
        this.usr = usr;
        this.variable = var;

        if (var.name.length != 0) {
            // Prefer using the name because it is also the c/c++ identifier.
            // The same name in a namespace would mean a collition. Breakin the
            // one definition rule.
            setUniqueId(var.name);
        } else {
            setUniqueId(usr);
        }
    }

    this(USRType usr, TypeKindAttr type, CppVariable name) @safe pure nothrow {
        this(usr, TypeKindVariable(type, name));
    }

    string toString() @trusted {
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);

        return cast(string) buf;
    }

    /// If formatSpec is "%u" then the USR will be put as a comment.
    void toString(Writer, Char)(scope Writer sink, FormatSpec!Char fmt) {
        import std.format : formattedWrite;
        import std.range : put;
        import cpptooling.data : TypeKind, Void;

        void handler() @trusted {
            formattedWrite(sink, "%s;", variable.type.toStringDecl(variable.name));
            if (!usr.isNull && fmt.spec == 'u') {
                put(sink, " // ");
                put(sink, usr.get);
            }
        }

        variable.type.kind.info.match!((TypeKind.RecordInfo t) => handler,
                (TypeKind.FuncInfo t) => handler, (TypeKind.FuncPtrInfo t) => handler,
                (TypeKind.FuncSignatureInfo t) => handler, (TypeKind.PrimitiveInfo t) => handler,
                (TypeKind.SimpleInfo t) => handler, (TypeKind.TypeRefInfo t) => handler,
                (TypeKind.ArrayInfo t) => handler,
                (TypeKind.PointerInfo t) => handler, (TypeKind.CtorInfo) {
            logger.error("Assumption broken. A global variable with the type of a Constructor");
        }, (TypeKind.DtorInfo) {
            logger.error("Assumption broken. A global variable with the type of a Destructor");
        }, (Void) {
            logger.error("Type of global variable is null. Identifier ", variable.name);
        });
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
        void put(CxParam p) {
            params_ ~= p;
        }

        auto paramRange() @nogc @safe pure nothrow {
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

        pure @nogc nothrow {
            bool isVirtual() {
                import std.algorithm : among;

                with (MemberVirtualType) {
                    return classification_.get.among(Virtual, Pure) != 0;
                }
            }

            bool isPure() {
                with (MemberVirtualType) {
                    return classification_.get == Pure;
                }
            }

            MemberVirtualType classification() {
                return classification_.get;
            }

            CppAccess accessType() {
                return accessType_;
            }

            CppMethodName name() {
                return name_.get;
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
        pure @nogc nothrow {
            bool isConst() const {
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
    mixin mixinUniqueId!size_t;

    Nullable!USRType usr;
    Nullable!Language language;

    private {
        CFunctionName name_;
        CxParam[] params;
        CxReturnType returnType_;
        VariadicType isVariadic_;
        StorageClass storageClass_;
    }

    //invariant () {
    //    if (!usr.isNull) {
    //        assert(usr.get.length > 0);
    //        assert(name_.length > 0);
    //        assert(returnType_.toStringDecl.length > 0);
    //
    //        foreach (p; params) {
    //            assertVisit(p);
    //        }
    //    }
    //}

    /// C function representation.
    this(USRType usr, CFunctionName name, CxParam[] params_, CxReturnType return_type,
            VariadicType is_variadic, StorageClass storage_class) @safe {
        this.usr = usr;
        this.name_ = name;
        this.returnType_ = return_type;
        this.isVariadic_ = is_variadic;
        this.storageClass_ = storage_class;

        this.params = params_.dup;

        //setUniqueId(format("%s(%s)", name, params.joinParamTypes));
    }

    /// Function with no parameters.
    this(USRType usr, CFunctionName name, CxReturnType return_type) @safe {
        this(usr, name, CxParam[].init, return_type, VariadicType.no, StorageClass.None);
    }

    /// Function with no parameters and returning void.
    this(USRType usr, CFunctionName name) @safe {
        auto void_ = CxReturnType(makeSimple("void"));
        this(usr, name, CxParam[].init, void_, VariadicType.no, StorageClass.None);
    }

    void toString(Writer, Char)(scope Writer sink, FormatSpec!Char fmt) @trusted {
        import std.conv : to;
        import std.format : formattedWrite;
        import std.range : put;

        formattedWrite(sink, "%s %s(%s); // %s", returnType_.toStringDecl,
                name_, params.joinParams, to!string(storageClass_));

        if (!usr.isNull && fmt.spec == 'u') {
            put(sink, " ");
            put(sink, usr.get);
        }
    }

    string toString() @trusted {
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);

        return cast(string) buf;
    }

@safe nothrow pure @nogc:

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
struct CppCtor {
    Nullable!USRType usr;

    private {
        CppAccess accessType_;
        Nullable!CppMethodName name_;
    }

    invariant () {
        if (!name_.isNull) {
            assert(usr.isNull || usr.get.length > 0);
            assert(name_.get.length > 0);
            foreach (p; params_) {
                assertVisit(p);
            }
        }
    }

    this(USRType usr, CppMethodName name, CxParam[] params, CppAccess access) @safe {
        this.usr = usr;
        this.name_ = name;
        this.accessType_ = access;
        this.params_ = params.dup;

        setUniqueId(format("%s(%s)", name_, paramRange.joinParamTypes));
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        helperPutComments(w);
        formattedWrite(w, "%s(%s)", name_, paramRange.joinParams);
        put(w, ";");
        if (!usr.isNull && fmt.spec == 'u') {
            formattedWrite(w, " // %s", usr);
        }
    }

@safe:
    mixin mixinCommentHelper;
    mixin mixinUniqueId!size_t;
    mixin CppMethodGeneric.Parameters;

    mixin(standardToString);

    auto accessType() {
        return accessType_;
    }

    auto name() {
        return name_;
    }
}

struct CppDtor {
    // TODO remove the Nullable, if possible.
    Nullable!USRType usr;

    invariant () {
        if (!name_.isNull) {
            assert(usr.isNull || usr.get.length > 0);
            assert(name_.get.length > 0);
            assert(classification_ != MemberVirtualType.Unknown);
        }
    }

    this(USRType usr, CppMethodName name, CppAccess access, CppVirtualMethod virtual) @safe {
        this.usr = usr;
        this.classification_ = virtual;
        this.accessType_ = access;
        this.name_ = name;

        setUniqueId(name_.get);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
        import std.format : formattedWrite;

        helperPutComments(w);
        formattedWrite(w, "%s%s();", helperVirtualPre(classification_.get), name_);
        if (!usr.isNull && fmt.spec == 'u') {
            formattedWrite(w, " // %s", usr);
        }
    }

@safe:
    mixin mixinCommentHelper;
    mixin mixinUniqueId!size_t;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin(standardToString);
}

struct CppMethod {
    Nullable!USRType usr;

    invariant {
        if (!name_.isNull) {
            assert(usr.isNull || usr.get.length > 0);
            assert(name_.get.length > 0);
            assert(returnType_.toStringDecl.length > 0);
            assert(classification_ != MemberVirtualType.Unknown);
            foreach (p; params_) {
                assertVisit(p);
            }
        }
    }

    this(USRType usr, CppMethodName name, CxParam[] params, CxReturnType return_type,
            CppAccess access, CppConstMethod const_, CppVirtualMethod virtual) @safe {
        this.usr = usr;
        this.classification_ = virtual;
        this.accessType_ = access;
        this.name_ = name;
        this.returnType_ = return_type;
        this.isConst_ = const_;

        this.params_ = params.dup;

        setUniqueId(format("%s(%s)", name, paramRange.joinParamTypes));
    }

    /// Function with no parameters.
    this(USRType usr, CppMethodName name, CxReturnType return_type,
            CppAccess access, CppConstMethod const_, CppVirtualMethod virtual) @safe {
        this(usr, name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(USRType usr, CppMethodName name, CppAccess access, CppConstMethod const_ = CppConstMethod(false),
            CppVirtualMethod virtual = CppVirtualMethod(MemberVirtualType.Normal)) @safe {
        auto void_ = CxReturnType(makeSimple("void"));
        this(usr, name, CxParam[].init, void_, access, const_, virtual);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) @safe {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        helperPutComments(w);
        put(w, helperVirtualPre(classification_.get));
        put(w, returnType_.toStringDecl);
        put(w, " ");
        put(w, name_.get);
        formattedWrite(w, "(%s)", paramRange.joinParams);
        put(w, helperConst(isConst));
        put(w, helperVirtualPost(classification_.get));
        put(w, ";");

        if (!usr.isNull && fmt.spec == 'u') {
            put(w, " // ");
            put(w, usr.get);
        }
    }

@safe:
    mixin mixinCommentHelper;
    mixin mixinUniqueId!size_t;
    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.MethodProperties;
    mixin(standardToString);
}

struct CppMethodOp {
    Nullable!USRType usr;

    invariant () {
        if (!name_.isNull) {
            assert(name_.get.length > 0);
            assert(returnType_.toStringDecl.length > 0);
            assert(classification_ != MemberVirtualType.Unknown);

            foreach (p; params_) {
                assertVisit(p);
            }
        }
    }

    this(USRType usr, CppMethodName name, CxParam[] params, CxReturnType return_type,
            CppAccess access, CppConstMethod const_, CppVirtualMethod virtual) @safe {
        this.usr = usr;
        this.classification_ = virtual;
        this.accessType_ = access;
        this.name_ = name;
        this.isConst_ = const_;
        this.returnType_ = return_type;

        this.params_ = params.dup;

        setUniqueId(format("%s(%s)", name, paramRange.joinParamTypes));
    }

    /// Operator with no parameters.
    this(USRType usr, CppMethodName name, CxReturnType return_type,
            CppAccess access, CppConstMethod const_, CppVirtualMethod virtual) @safe {
        this(usr, name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Operator with no parameters and returning void.
    this(USRType usr, CppMethodName name, CppAccess access, CppConstMethod const_ = CppConstMethod(false),
            CppVirtualMethod virtual = CppVirtualMethod(MemberVirtualType.Normal)) @safe {
        auto void_ = CxReturnType(makeSimple("void"));
        this(usr, name, CxParam[].init, void_, access, const_, virtual);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        helperPutComments(w);
        put(w, helperVirtualPre(classification_.get));
        put(w, returnType_.toStringDecl);
        put(w, " ");
        put(w, name_.get);
        formattedWrite(w, "(%s)", paramRange.joinParams);
        put(w, helperConst(isConst));
        put(w, helperVirtualPost(classification_.get));
        put(w, ";");

        if (!usr.isNull && fmt.spec == 'u') {
            put(w, " // ");
            put(w, usr.get);
        }
    }

@safe:
    mixin mixinCommentHelper;
    mixin mixinUniqueId!size_t;
    mixin CppMethodGeneric.Parameters;
    mixin CppMethodGeneric.StringHelperVirtual;
    mixin CppMethodGeneric.BaseProperties;
    mixin CppMethodGeneric.MethodProperties;

    mixin(standardToString);

    /// The operator type, aka in C++ the part after "operator"
    auto op()
    in {
        assert(name_.get.length > 8);
    }
    do {
        return CppMethodName((cast(string) name_.get)[8 .. $]);
    }
}

struct CppInherit {
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

    this(CppClassName name, CppAccess access) @safe {
        this.name_ = name;
        this.access_ = access;
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
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

@safe:
    void put(CppNs ns) {
        this.ns ~= ns;
    }

    auto nsRange() @nogc @safe pure nothrow inout {
        return ns;
    }

    mixin(standardToString);

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
        auto r = chain(ns.payload.map!(a => cast(string) a),
                       only(cast(string) name_))
            .joiner("::")
            .text();
        return FullyQualifiedNameType(r);
        // dfmt on
    }
}

struct CppClass {
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    static import cpptooling.data.class_classification;

    alias CppFunc = SumType!(CppMethod, CppMethodOp, CppCtor, CppDtor);

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
    }

    this(CppClassName name, CppInherit[] inherits, CppNsStack ns) @safe
    out {
        assert(name_.length > 0);
    }
    do {
        import std.array : array;
        import std.algorithm : map, each;

        this.name_ = name;
        this.reside_in_ns = CppNsStack(ns.dup);

        this.inherits_ = inherits.map!((a) {
            auto r = CppInherit(a.name, a.access);
            a.nsRange.each!(b => r.put(b));
            return r;
        }).array();

        setUniqueId(fullyQualifiedName);
    }

    //TODO remove
    this(CppClassName name, CppInherit[] inherits) @safe
    out {
        assert(name_.length > 0);
    }
    do {
        this(name, inherits, CppNsStack.init);
    }

    //TODO remove
    this(CppClassName name) @safe
    out {
        assert(name_.length > 0);
    }
    do {
        this(name, CppInherit[].init, CppNsStack.init);
    }

    // TODO remove @safe. it isn't a requirement that the user provided Writer is @safe.
    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) @safe {
        import std.algorithm : copy, joiner, map, each;
        import std.ascii : newline;
        import std.conv : to;
        import std.format : formattedWrite;
        import std.range : takeOne, put, save;

        helperPutComments(w);
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
            put(w, usr.get);
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

    void put(T)(T func)
            if (is(Unqual!T == CppMethod) || is(Unqual!T == CppCtor)
                || is(Unqual!T == CppDtor) || is(Unqual!T == CppMethodOp)) {
        static if (is(Unqual!T == T)) {
            auto f = () @trusted { return CppFunc(func); }();
        } else {
            // TODO remove this hack. It is unsafe.
            auto f = () @trusted {
                Unqual!T tmp;
                tmp = cast(Unqual!T) func;
                return CppFunc(tmp);
            }();
        }

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

@safe:
    mixin mixinUniqueId!size_t;
    mixin mixinCommentHelper;

    mixin(standardToString);

    void put(CppFunc f) {
        static void internalPut(T)(ref T class_, CppFunc f) @trusted {
            // dfmt off
            f.match!((CppMethod a) => class_.put(a),
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

        return reside_in_ns.payload.retro;
    }

    auto commentRange() @nogc {
        return comments;
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

    FullyQualifiedNameType fullyQualifiedName() @trusted {
        //TODO optimize by only calculating once.

        import std.array : array;
        import std.algorithm : map, joiner;
        import std.range : takeOne, only, chain, takeOne;
        import std.utf : byChar;

        // dfmt off
        auto fqn = chain(
                         reside_in_ns.payload.map!(a => cast(string) a).joiner("::"),
                         reside_in_ns.payload.takeOne.map!(a => "::").joiner(),
                         only(cast(string) name_).joiner()
                        );
        return FullyQualifiedNameType(fqn.byChar.array.idup);
        // dfmt on
    }
}

/// Dictates how the namespaces are merged.
enum MergeMode {
    /// Merge everything except nested namespaces.
    shallow,
    /// Merge everything.
    full
}

@safe struct CppNamespace {
    import std.algorithm : sort, map;
    import std.array : array;
    import cpptooling.data.symbol.types : FullyQualifiedNameType;
    import my.set;

    mixin mixinUniqueId!size_t;

    private {
        CppNs name_;

        CppNsStack stack;

        CppClass[] classes;
        CppNamespace[] namespaces;

        CxGlobalVariable[] globals;
        Set!string globalIds;

        CFunction[] funcs;
        Set!string funcIds;
    }

    static auto makeAnonymous() nothrow {
        auto rval = CppNamespace(CppNsStack.init);
        rval.setUniqueId(makeUniqueUSR);
        return rval;
    }

    /// A namespace without any nesting.
    static auto make(CppNs name) nothrow {
        auto rval = CppNamespace(CppNsStack([name]));
        return rval;
    }

    this(CppNsStack stack) nothrow {
        import std.algorithm : joiner;
        import std.container : make;
        import std.digest.crc : crc32Of;
        import std.utf : byChar;

        this.stack = CppNsStack(stack.dup);

        if (stack.length > 0) {
            this.name_ = stack[$ - 1];

            try {
                ubyte[4] hash = () @trusted {
                    return this.stack.joiner.byChar.crc32Of();
                }();
                this.id_ = ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
            } catch (Exception ex) {
                this.setUniqueId(makeUniqueUSR);
            }
        } else {
            // anonymous namespace
            this.setUniqueId(makeUniqueUSR);
        }
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
        import std.algorithm : map, joiner;
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.meta : AliasSeq;
        import std.range : takeOne, retro, put;

        auto ns_top_name = stack.payload.retro.takeOne.map!(a => cast(string) a).joiner();
        auto ns_full_name = stack.payload.map!(a => cast(string) a).joiner("::");

        formattedWrite(w, "namespace %s { //%s", ns_top_name, ns_full_name);

        if (fmt.spec == 'u') {
            formattedWrite(w, " %s", id);
        }

        put(w, newline);

        foreach (range; AliasSeq!("globalRange()", "funcRange()", "classes", "namespaces")) {
            foreach (a; mixin(range)) {
                a.toString(w, fmt);
                put(w, newline);
            }
        }

        formattedWrite(w, "} //NS:%s", ns_top_name);
    }

    /** Merge the content of other_ns into this.
     *
     * The namespaces do NOT become nested. Use `put` instead.
     *
     * The order of the items are preserved.
     * The items are deduplicated via the `id` attribute.
     *
     * Implemented to be cheap but we aware that after this operation the two
     * namespaces will point to the same elements.  A mutation in one of them
     * will affect both.
     */
    void merge(ref CppNamespace other_ns, MergeMode mode) @safe pure nothrow {
        foreach (item; other_ns.funcs)
            put(item);
        foreach (item; other_ns.globals)
            put(item);

        // not a RedBlackTree so must ensure deduplication via a AA

        bool[size_t] exists;
        foreach (ref item; classRange) {
            exists[item.id] = true;
        }

        // only copy items from other NS that are NOT in this NS.
        // assumption: two items with the same ID are the same content wise.
        foreach (ref item; other_ns.classRange) {
            if (item.id !in exists) {
                put(item);
            }
        }

        if (mode == MergeMode.full) {
            mergeRecursive(other_ns);
        }
    }

    private void mergeRecursive(ref CppNamespace other_ns) @safe pure nothrow {
        void slowMerge(ref CppNamespace other_ns) @safe pure nothrow {
            foreach (ref item; namespaceRange) {
                if (item.id == other_ns.id) {
                    item.merge(other_ns, MergeMode.full);
                    return;
                }
            }

            // should NEVER happen. If it happens then some mutation has
            // happened in parallel.
            // It has already been proven via exists that the namespace exist
            // among the namespaces this object have.
            assert(0);
        }

        bool[size_t] exists;

        foreach (ref item; namespaceRange) {
            exists[item.id] = true;
        }

        foreach (ref item; other_ns.namespaceRange) {
            if (item.id in exists) {
                slowMerge(item);
            } else {
                this.put(item);
            }
        }
    }

    /// Put item in storage.
    void put(CFunction f) @trusted pure nothrow {
        if (f.usr.isNull)
            return;

        if (f.usr.get !in funcIds) {
            funcs ~= f;
            funcIds.add(f.usr.get);
        }
    }

    /// ditto
    void put(CppClass s) pure nothrow {
        classes ~= s;
    }

    /// ditto
    void put(CppNamespace ns) pure nothrow {
        // TODO this is slow.

        foreach (ref item; namespaceRange) {
            if (item.id == ns.id) {
                item.merge(ns, MergeMode.full);
                return;
            }
        }

        namespaces ~= ns;
    }

    /// ditto
    void put(CxGlobalVariable g) @trusted pure nothrow {
        if (g.name !in globalIds) {
            globals ~= g;
            globalIds.add(g.name);
        }
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
    auto funcRange() @trusted pure nothrow {
        // TODO: there is a bug with sort which corrupts the USR of the elements.
        // repeatable by calling globalRange two times. The second time one
        // element is corrupted.
        auto indexes = new size_t[funcs.length];
        try {
            makeIndex!((a, b) => a.usr.get < b.usr.get)(funcs, indexes);
        } catch (Exception e) {
        }
        return indexes.map!(a => funcs[a]).array;
    }

    /// Range of namespaces residing in this namespace.
    auto namespaceRange() @nogc pure nothrow {
        return namespaces;
    }

    /// Global variables residing in this namespace.
    auto globalRange() @trusted pure nothrow {
        // TODO: there is a bug with sort which corrupts the USR of the elements.
        // repeatable by calling globalRange two times. The second time one
        // element is corrupted.
        auto indexes = new size_t[globals.length];
        try {
            makeIndex!((a, b) => a.name < b.name)(globals, indexes);
        } catch (Exception e) {
        }
        return indexes.map!(a => globals[a]).array;
    }

    mixin(standardToString);

    /// If the namespace is anonymous, aka has no name.
    bool isAnonymous() pure nothrow {
        return name_.length == 0;
    }

    /// Returns: True if completely empty.
    bool empty() pure nothrow {
        return !(classes.length || funcs.length || namespaces.length || globals.length);
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
        import std.utf : byChar;

        // dfmt off
        auto fqn = stack.payload.map!(a => cast(string) a).joiner("::");
        return FullyQualifiedNameType(fqn.byChar.array().idup);
        // dfmt on
    }
}

/** The root of the data structure of the semantic representation of the
 * analyzed C++ source.
 */
struct CppRoot {
    import std.algorithm : sort, map;
    import std.array : array;
    import my.set;

    private {
        CppNamespace[] ns;
        CppClass[] classes;

        CxGlobalVariable[] globals;
        Set!string globalIds;

        CFunction[] funcs;
        Set!string funcIds;
    }

    /// Recrusive stringify the content for human readability.
    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
        import std.ascii : newline;
        import std.meta : AliasSeq;
        import std.range : put;

        foreach (range; AliasSeq!("globalRange()", "funcRange()", "classes", "ns")) {
            foreach (a; mixin(range)) {
                a.toString(w, fmt);
                put(w, newline);
            }
        }
    }

@safe:

    /** Merge the roots.
     *
     * Implemented to be cheap but we aware that after this operation the two
     * root's will point to the same elements. A mutation in one of them will
     * affect both.
     */
    void merge(ref CppRoot root, MergeMode mode) nothrow {
        foreach (item; root.funcs)
            put(item);
        foreach (item; root.globals)
            put(item);

        // not a RedBlackTree so must ensure deduplication via a AA

        bool[size_t] exists;
        foreach (ref item; classRange) {
            exists[item.id] = true;
        }

        foreach (ref item; root.classRange) {
            if (item.id !in exists) {
                put(item);
            }
        }

        if (mode == MergeMode.full) {
            mergeRecursive(root);
        }
    }

    private void mergeRecursive(ref CppRoot root) @safe pure nothrow {
        void slowMerge(ref CppNamespace other_ns) @safe pure nothrow {
            foreach (ref item; namespaceRange) {
                if (item.id == other_ns.id) {
                    item.merge(other_ns, MergeMode.full);
                    return;
                }
            }

            // should NEVER happen. If it happens then some mutation has
            // happened in parallel.
            // It has already been proven via exists that the namespace exist
            // among the namespaces this object have.
            assert(0);
        }

        bool[size_t] exists;

        foreach (ref item; namespaceRange) {
            exists[item.id] = true;
        }

        foreach (ref item; root.namespaceRange) {
            if (item.id in exists) {
                slowMerge(item);
            } else {
                this.put(item);
            }
        }
    }

    /// Put item in storage.
    void put(CFunction f) @trusted pure nothrow {
        if (f.usr.isNull)
            return;

        if (f.usr.get !in funcIds) {
            funcs ~= f;
            funcIds.add(f.usr.get);
        }
    }

    /// ditto
    void put(CppClass s) pure nothrow {
        classes ~= s;
    }

    /// ditto
    void put(CppNamespace ns) pure nothrow {
        // TODO this is slow.

        foreach (ref item; namespaceRange) {
            if (item.id == ns.id) {
                item.merge(ns, MergeMode.full);
                return;
            }
        }

        this.ns ~= ns;
    }

    /// ditto
    void put(CxGlobalVariable g) @trusted nothrow {
        if (!g.usr.isNull && g.name !in globalIds) {
            globals ~= g;
            globalIds.add(g.name);
        }
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
    auto funcRange() @trusted {
        // TODO: there is a bug with sort which corrupts the USR of the elements.
        // repeatable by calling globalRange two times. The second time one
        // element is corrupted.
        auto indexes = new size_t[funcs.length];
        try {
            makeIndex!((a, b) => a.usr.get < b.usr.get)(funcs, indexes);
        } catch (Exception e) {
        }
        return indexes.map!(a => funcs[a]).array;
    }

    /// ditto
    auto globalRange() @trusted {
        // TODO: there is a bug with sort which corrupts the USR of the elements.
        // repeatable by calling globalRange two times. The second time one
        // element is corrupted.
        auto indexes = new size_t[globals.length];
        try {
            makeIndex!((a, b) => a.name < b.name)(globals, indexes);
        } catch (Exception e) {
        }
        return indexes.map!(a => globals[a]).array;
    }

    /// Cast to string representation
    T opCast(T : string)() {
        return this.toString;
    }

    mixin(standardToString);
}

@("Test of c-function")
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

@("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public));
    shouldEqual(m.isConst, false);
    shouldEqual(m.classification, MemberVirtualType.Normal);
    shouldEqual(m.name, "voider");
    shouldEqual(m.params_.length, 0);
    shouldEqual(m.returnType.toStringDecl("x"), "void x");
    shouldEqual(m.accessType, AccessType.Public);
}

@("Test creating a CppMethod with multiple parameters")
unittest {
    auto tk = makeSimple("char*");
    tk.attr.isPtr = Yes.isPtr;
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto m = CppMethod(dummyUSR, CppMethodName("none"), [p, p], CxReturnType(tk),
            CppAccess(AccessType.Public), CppConstMethod(true),
            CppVirtualMethod(MemberVirtualType.Virtual));

    shouldEqual(format("%u", m), "virtual char* none(char* x, char* x) const; // dummyUSR");
}

@("should represent the operator as a string")
unittest {
    auto m = CppMethodOp(dummyUSR, CppMethodName("operator="), CppAccess(AccessType.Public));

    shouldEqual(format("%u", m), "void operator=(); // dummyUSR");
}

@("should separate the operator keyword from the actual operator")
unittest {
    auto m = CppMethodOp(dummyUSR, CppMethodName("operator="), CppAccess(AccessType.Public));

    shouldEqual(m.op, "=");
}

@("should represent a class with one public method")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    shouldEqual(c.methods_pub.length, 1);
    shouldEqual(format("%u", c), "class Foo { // Normal
public:
  void voider(); // dummyUSR
}; //Class:Foo");
}

@("should represent a class with one public operator overload")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto op = CppMethodOp(dummyUSR, CppMethodName("operator="), CppAccess(AccessType.Public));
    c.put(op);

    shouldEqual(format("%u", c), "class Foo { // Normal
public:
  void operator=(); // dummyUSR
}; //Class:Foo");
}

@("Create an anonymous namespace struct")
unittest {
    auto n = CppNamespace(CppNsStack.init);
    shouldEqual(n.name.length, 0);
    shouldEqual(n.isAnonymous, true);
}

@("Create a namespace struct two deep")
unittest {
    auto stack = CppNsStack([CppNs("foo"), CppNs("bar")]);
    auto n = CppNamespace(stack);
    shouldEqual(cast(string) n.name, "bar");
    shouldEqual(n.isAnonymous, false);
}

@("Test of iterating over parameters in a class")
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

@("Test of toString for a free function")
unittest {
    auto ptk = makeSimple("char*");
    ptk.attr.isPtr = Yes.isPtr;
    auto rtk = makeSimple("int");
    auto f = CFunction(dummyUSR, CFunctionName("nothing"), [
            makeCxParam(TypeKindVariable(ptk, CppVariable("x"))),
            makeCxParam(TypeKindVariable(ptk, CppVariable("y")))
            ], CxReturnType(rtk), VariadicType.no, StorageClass.None);

    shouldEqual(format("%u", f), "int nothing(char* x, char* y); // None dummyUSR");
}

@("Test of Ctor's")
unittest {
    auto tk = makeSimple("char*");
    tk.attr.isPtr = Yes.isPtr;
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto ctor = CppCtor(dummyUSR, CppMethodName("ctor"), [p, p], CppAccess(AccessType.Public));

    shouldEqual(format("%u", ctor), "ctor(char* x, char* x); // dummyUSR");
}

@("Test of Dtor's")
unittest {
    auto dtor = CppDtor(dummyUSR, CppMethodName("~dtor"),
            CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual));

    shouldEqual(format("%u", dtor), "virtual ~dtor(); // dummyUSR");
}

@("Test of toString for CppClass")
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

    shouldEqual(format("%u", c), "class Foo { // Abstract
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

@("should be a class in a ns in the comment")
unittest {
    auto ns = CppNsStack([CppNs("a_ns"), CppNs("another_ns")]);
    auto c = CppClass(CppClassName("A_Class"), CppInherit[].init, ns);

    shouldEqual(c.toString, "class A_Class { // Unknown
}; //Class:a_ns::another_ns::A_Class");
}

@("should contain the inherited classes")
unittest {
    CppInherit[] inherit;
    inherit ~= CppInherit(CppClassName("pub"), CppAccess(AccessType.Public));
    inherit ~= CppInherit(CppClassName("prot"), CppAccess(AccessType.Protected));
    inherit ~= CppInherit(CppClassName("priv"), CppAccess(AccessType.Private));

    auto c = CppClass(CppClassName("Foo"), inherit);

    shouldEqual(c.toString, "class Foo : public pub, protected prot, private priv { // Unknown
}; //Class:Foo");
}

@("should contain nested classes")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    c.put(CppClass(CppClassName("Pub")), AccessType.Public);
    c.put(CppClass(CppClassName("Prot")), AccessType.Protected);
    c.put(CppClass(CppClassName("Priv")), AccessType.Private);

    shouldEqual(c.toString, "class Foo { // Unknown
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

@("should be a virtual class")
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

    shouldEqual(format("%u", c), "class Foo { // Virtual
public:
  Foo(); // dummyUSR
  virtual ~Foo(); // dummyUSR
  virtual int wun(); // dummyUSR
}; //Class:Foo");
}

@("should be a pure virtual class")
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

    shouldEqual(format("%u", c), "class Foo { // Pure
public:
  Foo(); // dummyUSR
  virtual ~Foo(); // dummyUSR
  virtual int wun() = 0; // dummyUSR
}; //Class:Foo");
}

@("Test of toString for CppNamespace")
unittest {
    auto ns = CppNamespace.make(CppNs("simple"));

    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public)));
    ns.put(c);

    shouldEqual(format("%s", ns), "namespace simple { //simple
class Foo { // Normal
public:
  void voider();
}; //Class:Foo
} //NS:simple");
}

@("Should show nesting of namespaces as valid C++ code")
unittest {
    auto stack = CppNsStack([CppNs("foo"), CppNs("bar")]);
    auto n = CppNamespace(stack);
    shouldEqual(n.toString, "namespace bar { //foo::bar
} //NS:bar");
}

@("Test of toString for CppRoot")
unittest {
    CppRoot root;

    { // free function
        auto f = CFunction(dummyUSR, CFunctionName("nothing"));
        root.put(f);
    }

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(dummyUSR, CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    root.put(c);

    root.put(CppNamespace.make(CppNs("simple")));

    shouldEqual(format("%s", root), "void nothing(); // None
class Foo { // Normal
public:
  void voider();
}; //Class:Foo
namespace simple { //simple
} //NS:simple
");
}

@("CppNamespace.toString should return nested namespace")
unittest {
    auto stack = [CppNs("Depth1"), CppNs("Depth2"), CppNs("Depth3")];
    auto depth1 = CppNamespace(CppNsStack(stack[0 .. 1]));
    auto depth2 = CppNamespace(CppNsStack(stack[0 .. 2]));
    auto depth3 = CppNamespace(CppNsStack(stack[0 .. $]));

    depth2.put(depth3);
    depth1.put(depth2);

    shouldEqual(depth1.toString, "namespace Depth1 { //Depth1
namespace Depth2 { //Depth1::Depth2
namespace Depth3 { //Depth1::Depth2::Depth3
} //NS:Depth3
} //NS:Depth2
} //NS:Depth1");
}

@("Create anonymous namespace")
unittest {
    auto n = CppNamespace.makeAnonymous();

    shouldEqual(n.toString, "namespace  { //
} //NS:");
}

@("Add a C-func to a namespace")
unittest {
    auto n = CppNamespace.makeAnonymous();
    auto f = CFunction(dummyUSR, CFunctionName("nothing"));
    n.put(f);

    shouldEqual(format("%s", n), "namespace  { //
void nothing(); // None
} //NS:");
}

@("should be a hash value based on string representation")
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

@("should be a global definition")
unittest {
    auto v0 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    auto v1 = CxGlobalVariable(dummyUSR, makeSimple("int"), CppVariable("y"));

    shouldEqual(format("%u", v0), "int x; // dummyUSR");
    shouldEqual(format("%u", v1), "int y; // dummyUSR");
}

@("Should be globals stored in the root object")
unittest {
    auto v = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    auto n = CppNamespace.makeAnonymous();
    CppRoot r;
    n.put(v);
    r.put(v);
    r.put(n);

    shouldEqual(format("%s", r), "int x;
namespace  { //
int x;
} //NS:
");
}

@("should be possible to sort the data structures")
unittest {
    import std.array : array;

    auto v0 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    auto v1 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));
    CppRoot r;
    r.put(v0);
    r.put(v1);
    r.put(v0);

    auto s = r.globalRange;
    shouldEqual(s.array().length, 1);
}

@("should be proper access specifiers for a inherit reference, no nesting")
unittest {
    auto ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Public));
    shouldEqual("public Class", ih.toString);

    ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Protected));
    shouldEqual("protected Class", ih.toString);

    ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Private));
    shouldEqual("private Class", ih.toString);
}

@("should be a inheritances of a class in namespaces")
unittest {
    auto ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Public));
    ih.put(CppNs("ns1"));
    ih.toString.shouldEqual("public ns1::Class");

    ih.put(CppNs("ns2"));
    ih.toString.shouldEqual("public ns1::ns2::Class");

    ih.put(CppNs("ns3"));
    ih.toString.shouldEqual("public ns1::ns2::ns3::Class");
}

@("should be a class that inherits")
unittest {
    auto ih = CppInherit(CppClassName("Class"), CppAccess(AccessType.Public));
    ih.put(CppNs("ns1"));

    auto c = CppClass(CppClassName("A"));
    c.put(ih);

    shouldEqual(c.toString, "class A : public ns1::Class { // Unknown
}; //Class:A");
}

@("Should be a class with a data member")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto tk = makeSimple("int");
    c.put(TypeKindVariable(tk, CppVariable("x")), AccessType.Public);

    shouldEqual(c.toString, "class Foo { // Unknown
public:
  int x;
}; //Class:Foo");
}

@("Should be an abstract class")
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

    shouldEqual(format("%u", c), "class Foo { // Abstract
public:
  ~Foo(); // dummyUSR
  virtual void wun() = 0; // dummyUSR
  virtual void gun(); // dummyUSR
}; //Class:Foo");

}

@("Should be a class with comments")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    c.comment("A comment");

    shouldEqual(c.toString, "// A comment
class Foo { // Unknown
}; //Class:Foo");
}

@("It is a c'tor with a multiline comment")
unittest {
    auto ctor = CppCtor(dummyUSR, CppMethodName("Foo"), CxParam[].init,
            CppAccess(AccessType.Public));
    ctor.comment("a multiline").comment("comment");

    shouldEqual(ctor.toString, "// a multiline
// comment
Foo();");
}

@("Shall merge two namespaces and preserve the order of the items")
unittest {
    import std.array : array;
    import std.algorithm : map;

    auto ns1 = CppNamespace(CppNsStack([CppNs("ns1")]));
    ns1.put(CppClass(CppClassName("ns1_class")));
    ns1.put(CxGlobalVariable(USRType("ns1_var"),
            TypeKindVariable(makeSimple("int"), CppVariable("ns1_var"))));
    ns1.put(CFunction(USRType("ns1_func"), CFunctionName("ns1_func")));

    auto ns2 = CppNamespace(CppNsStack([CppNs("ns2")]));
    ns2.put(CppClass(CppClassName("ns2_class")));
    ns2.put(CxGlobalVariable(USRType("ns2_var"),
            TypeKindVariable(makeSimple("int"), CppVariable("ns2_var"))));
    ns2.put(CFunction(USRType("ns2_func"), CFunctionName("ns2_func")));

    ns2.merge(ns1, MergeMode.shallow);

    ns2.classRange.map!(a => cast(string) a.name).array().shouldEqual([
        "ns2_class", "ns1_class"
    ]);
    ns2.globalRange.array().map!(a => cast(string) a.name).array()
        .shouldEqual(["ns1_var", "ns2_var"]);
    ns2.funcRange.array().map!(a => cast(string) a.name).array()
        .shouldEqual(["ns1_func", "ns2_func"]);
}

@("Shall merge two namespaces recursively")
unittest {
    import std.array : array;
    import std.algorithm : map;

    // Arrange
    auto ns1 = CppNamespace(CppNsStack([CppNs("ns1")]));
    auto ns2 = CppNamespace(CppNsStack([CppNs("ns2")]));
    auto ns3 = CppNamespace(CppNsStack([CppNs("ns3")]));

    // Act
    ns1.put(ns3);
    ns2.merge(ns1, MergeMode.shallow);

    // Assert
    // shallow do NOT merge
    ns2.namespaceRange.length.shouldEqual(0);

    // Act
    ns2.merge(ns1, MergeMode.full);
    ns2.namespaceRange.length.shouldEqual(1);
    ns2.namespaceRange.map!(a => cast(string) a.name).array().shouldEqual([
        "ns3"
    ]);
}

@("Shall merge two namespaces recursively with common namespaces merged to ensure no duplication")
unittest {
    import std.array : array;
    import std.algorithm : map;

    // Arrange
    auto ns1 = CppNamespace(CppNsStack([CppNs("ns1")]));
    auto ns4 = CppNamespace(CppNsStack([CppNs("ns4")]));

    auto ns2 = CppNamespace(CppNsStack([CppNs("ns2")]));
    ns2.put(CppClass(CppClassName("ns2_class")));
    ns2.put(CxGlobalVariable(USRType("ns2_var"),
            TypeKindVariable(makeSimple("int"), CppVariable("ns2_var"))));
    ns2.put(CFunction(USRType("ns2_func"), CFunctionName("ns2_func")));

    auto ns3_a = CppNamespace(CppNsStack([CppNs("ns3")]));
    ns3_a.put(CppClass(CppClassName("ns3_class")));
    ns3_a.put(CxGlobalVariable(USRType("ns3_var"),
            TypeKindVariable(makeSimple("int"), CppVariable("ns3_var"))));
    ns3_a.put(CFunction(USRType("ns3_func"), CFunctionName("ns3_func")));

    auto ns3_b = CppNamespace(CppNsStack([CppNs("ns3")]));
    // expected do be deduplicated
    ns3_b.put(CppClass(CppClassName("ns3_class")));
    ns3_b.put(CxGlobalVariable(USRType("ns3_var"),
            TypeKindVariable(makeSimple("int"), CppVariable("ns3_var"))));
    ns3_b.put(CFunction(USRType("ns3_func"), CFunctionName("ns3_func")));

    // expected to be merged in ns2 into the already existing ns3
    ns3_b.put(CppClass(CppClassName("ns3_b_class")));
    ns3_b.put(CxGlobalVariable(USRType("ns3_b_var"),
            TypeKindVariable(makeSimple("int"), CppVariable("ns3_b_var"))));
    ns3_b.put(CFunction(USRType("ns3_b_func"), CFunctionName("ns3_b_func")));

    // Act
    ns1.put(ns3_a);
    ns2.merge(ns1, MergeMode.shallow);

    // Assert
    // because of a shallow merge no namespaces are expected
    ns2.namespaceRange.length.shouldEqual(0);

    // Act
    ns2.merge(ns1, MergeMode.full);

    // Assert
    ns2.namespaceRange.length.shouldEqual(1);
    ns2.namespaceRange.map!(a => cast(string) a.name).array().shouldEqual([
        "ns3"
    ]);
    ns2.namespaceRange[0].classRange.length.shouldEqual(1);
    ns2.namespaceRange[0].funcRange.array().length.shouldEqual(1);
    ns2.namespaceRange[0].globalRange.array().length.shouldEqual(1);

    // Act
    ns4.put(ns3_b);
    ns2.merge(ns4, MergeMode.full);

    // Assert
    ns2.namespaceRange.length.shouldEqual(1);
    ns2.namespaceRange.map!(a => cast(string) a.name).array().shouldEqual([
        "ns3"
    ]);
    ns2.namespaceRange[0].classRange.length.shouldEqual(2);
    ns2.namespaceRange[0].funcRange.array().length.shouldEqual(2);
    ns2.namespaceRange[0].globalRange.array().length.shouldEqual(2);
}
