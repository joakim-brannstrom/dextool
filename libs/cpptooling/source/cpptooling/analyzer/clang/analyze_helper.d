/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Design.
 - Using named tuples as the result from analyze* to allow the tuples to add
   more data in the future without breaking existing code.
*/
module cpptooling.analyzer.clang.analyze_helper;

import logger = std.experimental.logger;

import std.meta : staticIndexOf;
import std.sumtype;
import std.traits : Unqual;
import std.typecons : tuple, Flag, Yes, No, Nullable;

import my.sumtype;

import clang.c.Index : CX_CXXAccessSpecifier, CX_StorageClass, CXLanguageKind;
import clang.Cursor : Cursor;
import clang.SourceLocation : SourceLocation;

import libclang_ast.ast : ClassTemplate, ClassTemplatePartialSpecialization,
    Constructor, CxxMethod, ClassDecl, CxxBaseSpecifier,
    Destructor, FieldDecl, FunctionDecl, StructDecl, TranslationUnit, UnionDecl, VarDecl, Visitor;

import cpptooling.analyzer.clang.type : retrieveType, TypeKind, TypeKindAttr,
    TypeResult, TypeResults, logTypeResult, TypeAttr;
import cpptooling.analyzer.clang.store : put;
import cpptooling.data : AccessType, VariadicType, CxParam, TypeKindVariable,
    CppVariable, LocationTag, Location, CxReturnType,
    CppVirtualMethod, CppMethodName, CppClassName, CppNs, CppAccess,
    StorageClass, CFunctionName, Language, CFunction, CxGlobalVariable;
import cpptooling.data.symbol : Container, USRType;

/// Convert Cursor attributes to enum representation.
private CppVirtualMethod classify(T)(T c) @safe if (is(Unqual!T == Cursor)) {
    import cpptooling.data.type : MemberVirtualType;

    auto is_virtual = MemberVirtualType.Normal;
    auto func = () @trusted { return c.func; }();

    if (!func.isValid) {
        // do nothing
    } else if (func.isPureVirtual) {
        is_virtual = MemberVirtualType.Pure;
    } else if (func.isVirtual) {
        is_virtual = MemberVirtualType.Virtual;
    }

    return CppVirtualMethod(is_virtual);
}

/// Convert a clang access specifier to dextool representation.
AccessType toAccessType(CX_CXXAccessSpecifier accessSpec) @safe {
    final switch (accessSpec) with (CX_CXXAccessSpecifier) {
    case cxxInvalidAccessSpecifier:
        return AccessType.Public;
    case cxxPublic:
        return AccessType.Public;
    case cxxProtected:
        return AccessType.Protected;
    case cxxPrivate:
        return AccessType.Private;
    }
}

StorageClass toStorageClass(CX_StorageClass storageClass) @safe pure nothrow @nogc {
    switch (storageClass) with (CX_StorageClass) {
    case extern_:
        return StorageClass.Extern;
    case static_:
        return StorageClass.Static;
    default:
        return StorageClass.None;
    }
}

private CxParam[] toCxParam(ref TypeKind kind, ref Container container) @safe {
    import std.array;
    import std.algorithm : map;
    import std.range : chain, zip, tee;
    import std.string : strip;
    import cpptooling.data.kind_type;

    auto tr_params = kind.info.match!((a => a.params), _ => (FuncInfoParam[]).init);

    // dfmt off
    auto params = zip(// range 1
                           tr_params
                           // lookup the parameters by the usr
                           .map!(a => container.find!TypeKind(a.usr))
                           // assuming none of the results to find failed
                           // merge the results to a range
                           .map!(a => a.front),
                           // range 2
                           tr_params)
        .map!((a) {
              if (a[1].isVariadic) {
                  return CxParam(VariadicType.yes);
              } else if (a[1].id.strip.length == 0) {
                  //TODO fix the above workaround with strip by fixing type.d
                  return CxParam(TypeKindAttr(a[0].get, a[1].attr));
              } else {
                  return CxParam(TypeKindVariable(TypeKindAttr(a[0].get, a[1].attr), CppVariable(a[1].id)));
              }
              });
    // dfmt on

    return () @trusted { return params.array(); }();
}

private auto locToTag(SourceLocation c_loc) {
    auto l = c_loc.expansion();
    auto into = LocationTag(Location(l.file.name(), l.line, l.column));

    return into;
}

private bool isOperator(CppMethodName name_) @safe {
    import std.algorithm : among;

    if (name_.length <= 8) {
        // "operator" keyword is 8 char long, thus an optimization to first
        // look at the length
        return false;
    } else if (name_[8 .. $].among("=", "==", "+=", "-=", "++", "--", "+", "-",
            "*", ">", ">=", "<", "<=", ">>", "<<")) {
        return true;
    }

    return false;
}

/** Correctly determine the language of a libclang Cursor.
 *
 * Combines an analysis of the name USR and a cursor query.
 */
Language toLanguage(const Cursor c) @safe
in {
    assert(c.isValid);
}
do {
    import std.algorithm : canFind;

    // assuming that the C++ USR always contains a '#'.
    if (c.usr.canFind('#')) {
        return Language.cpp;
    }

    final switch (c.language) with (CXLanguageKind) {
    case invalid:
        return Language.unknown;
    case c:
        return Language.c;
    case objC:
        return Language.unknown;
    case cPlusPlus:
        return Language.cpp;
    }
}

struct FunctionDeclResult {
    Flag!"isValid" isValid;
    TypeKindAttr type;
    CFunctionName name;
    TypeKindAttr returnType;
    VariadicType isVariadic;
    StorageClass storageClass;
    CxParam[] params;
    LocationTag location;
    Flag!"isDefinition" isDefinition;
    Language language;
}

FunctionDeclResult analyzeFunctionDecl(scope const FunctionDecl v,
        ref Container container, in uint indent) @safe {
    return analyzeFunctionDecl(v.cursor, container, indent);
}

// added trusted to get the compiler to shut up. the code works, just... needs scope.
FunctionDeclResult analyzeFunctionDecl(scope const Cursor c_in, ref Container container,
        in uint indent) @trusted
in {
    import clang.c.Index : CXCursorKind;

    () @trusted { assert(c_in.kind == CXCursorKind.functionDecl); }();
}
do {
    import std.algorithm : among;
    import std.functional : pipe;

    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.type : TypeKind, retrieveType, logTypeResult;
    import cpptooling.data : TypeResult, TypeKindAttr, CxParam, CFunctionName,
        CxReturnType, CFunction, VariadicType, LocationTag, StorageClass;
    import cpptooling.data.symbol : Container;

    // hint, start reading the function from the bottom up.
    // design is pipe and data transformation

    Nullable!TypeResults extractAndStoreRawType(const Cursor c) @trusted {
        auto tr = () @trusted { return retrieveType(c, container, indent); }();
        if (tr.isNull) {
            return tr;
        }

        bool fail;
        tr.get.primary.type.kind.info.match!(ignore!(TypeKind.FuncInfo),
                ignore!(TypeKind.TypeRefInfo), ignore!(TypeKind.SimpleInfo), (_) {
            fail = true;
        });
        if (fail)
            assert(0, "wrong type");

        put(tr, container, indent);

        return tr;
    }

    Nullable!TypeResults lookupRefToConcreteType(const Cursor c, Nullable!TypeResults tr) @trusted {
        if (tr.isNull) {
            return tr;
        }

        tr.get.primary.type.kind.info.match!((TypeKind.TypeRefInfo t) {
            // replace typeRef kind with the func
            auto kind = container.find!TypeKind(t.canonicalRef).front;
            tr.get.primary.type.kind = kind.get;
        }, (_) {});

        logTypeResult(tr, indent);
        tr.get.primary.type.kind.info.match!(ignore!(TypeKind.FuncInfo), (_) {
            assert(0, "wrong type");
        });

        return tr;
    }

    static struct ComposeData {
        TypeResults tr;
        CFunctionName name;
        LocationTag loc;
        VariadicType isVariadic;
        StorageClass storageClass;
        Flag!"isDefinition" is_definition;
        Language language;
    }

    static ComposeData getCursorData(const Cursor c, TypeResults tr) @safe {
        auto data = ComposeData(tr);

        data.name = CFunctionName(c.spelling);
        data.loc = locToTag(c.location());
        data.is_definition = cast(Flag!"isDefinition") c.isDefinition;
        data.storageClass = c.storageClass().toStorageClass;
        data.language = c.toLanguage;

        return data;
    }

    FunctionDeclResult composeFunc(ComposeData data) @safe {
        auto return_type = container.find!TypeKind(
                data.tr.primary.type.kind.info.match!(a => a.return_, _ => USRType.init));
        if (return_type.length == 0) {
            return FunctionDeclResult.init;
        }

        auto params = toCxParam(data.tr.primary.type.kind, container);

        VariadicType is_variadic;

        // according to C/C++ standard the last parameter is the only one
        // that can be a variadic, therefor only needing to peek at that
        // one.
        if (params.length > 0) {
            is_variadic = params[$ - 1].match!((VariadicType a) => a, _ => VariadicType.init);
        }

        auto attrs = data.tr.primary.type.kind.info.match!(a => a.returnAttr, _ => TypeAttr.init);
        return FunctionDeclResult(Yes.isValid, data.tr.primary.type, data.name,
                TypeKindAttr(return_type.front.get, attrs), is_variadic,
                data.storageClass, params, data.loc, data.is_definition, data.language);
    }

    FunctionDeclResult rval;
    auto r0 = extractAndStoreRawType(c_in);
    auto r1 = lookupRefToConcreteType(c_in, r0);
    if (!r1.isNull) {
        auto r2 = getCursorData(c_in, r1.get);
        rval = composeFunc(r2);
    }

    return rval;
}

struct VarDeclResult {
    TypeKindAttr type;
    CppVariable name;
    LocationTag location;
    USRType instanceUSR;
    StorageClass storageClass;
}

/// Analyze a variable declaration
VarDeclResult analyzeVarDecl(scope const VarDecl v, ref Container container, in uint indent) @safe {
    return analyzeVarDecl(v.cursor, container, indent);
}

/// ditto
VarDeclResult analyzeVarDecl(scope const Cursor v, ref Container container, in uint indent) @safe
in {
    import clang.c.Index : CXCursorKind;

    assert(v.kind == CXCursorKind.varDecl);
}
do {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.type : retrieveType;
    import cpptooling.data : CppVariable;

    auto type = () @trusted { return retrieveType(v, container, indent); }();
    put(type, container, indent);

    auto name = CppVariable(v.spelling);
    auto loc = locToTag(v.location());
    auto instance_usr = USRType(v.usr);
    // Assuming that all variable declarations have a USR
    assert(instance_usr.length > 0);

    // store the location to enable creating relations to/from this instance
    // USR.
    container.put(loc, instance_usr, Yes.isDefinition);

    auto storage = () @trusted { return v.storageClass.toStorageClass; }();

    return VarDeclResult(type.get.primary.type, name, loc, instance_usr, storage);
}

struct ConstructorResult {
    TypeKindAttr type;
    CppMethodName name;
    CxParam[] params;
    LocationTag location;
}

/** Analyze the node for actionable data.
 * Params:
 *   v = node
 *   container = container to store the type in
 *   indent = to use when logging
 *
 * Returns: analyzed data.
 */
auto analyzeConstructor(scope const Constructor v, ref Container container, in uint indent) @safe {
    auto type = () @trusted { return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto params = toCxParam(type.get.primary.type.kind, container);
    auto name = CppMethodName(v.cursor.spelling);

    return ConstructorResult(type.get.primary.type, name, params, type.get.primary.location);
}

struct DestructorResult {
    TypeKindAttr type;
    CppMethodName name;
    CppVirtualMethod virtualKind;
    LocationTag location;
}

/// ditto
auto analyzeDestructor(scope const Destructor v, ref Container container, in uint indent) @safe {
    auto type = () @trusted { return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppMethodName(v.cursor.spelling);
    auto virtual_kind = classify(v.cursor);

    return DestructorResult(type.get.primary.type, name, virtual_kind, type.get.primary.location);
}

struct CxxMethodResult {
    TypeKindAttr type;
    CppMethodName name;
    CxParam[] params;
    Flag!"isOperator" isOperator;
    CxReturnType returnType;
    CppVirtualMethod virtualKind;
    Flag!"isConst" isConst;
    LocationTag location;
}

CxxMethodResult analyzeCxxMethod(scope const CxxMethod v, ref Container container, in uint indent) @safe {
    return analyzeCxxMethod(v.cursor, container, indent);
}

/// ditto
CxxMethodResult analyzeCxxMethod(scope const Cursor v, ref Container container, in uint indent) @safe {
    auto type = () @trusted { return retrieveType(v, container, indent); }();
    type.get.primary.type.kind.info.match!(ignore!(TypeKind.FuncInfo), (_) {
        assert(0, "wrong type");
    });
    put(type, container, indent);

    auto name = CppMethodName(v.spelling);
    auto params = toCxParam(type.get.primary.type.kind, container);
    auto return_type = CxReturnType(TypeKindAttr(container.find!TypeKind(
            type.get.primary.type.kind.info.match!(a => a.return_, _ => USRType.init)).front.get,
            type.get.primary.type.kind.info.match!(a => a.returnAttr, _ => TypeAttr.init)));
    auto is_virtual = classify(v);

    return CxxMethodResult(type.get.primary.type, name, params,
            cast(Flag!"isOperator") isOperator(name), return_type, is_virtual,
            cast(Flag!"isConst") type.get.primary.type.attr.isConst, type.get.primary.location);
}

struct FieldDeclResult {
    TypeKindAttr type;
    CppVariable name;
    USRType instanceUSR;
    LocationTag location;
}

/// ditto
auto analyzeFieldDecl(scope const FieldDecl v, ref Container container, in uint indent) @safe {
    import cpptooling.analyzer.clang.type : makeEnsuredUSR;

    auto type = () @trusted { return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppVariable(v.cursor.spelling);

    auto instance_usr = makeEnsuredUSR(v.cursor, indent + 1);
    // Assuming that all field declarations have a USR
    assert(instance_usr.length > 0);

    auto loc = () @trusted { return locToTag(v.cursor.location()); }();
    // store the location to enable creating relations to/from this instance
    // USR.
    container.put(loc, instance_usr, Yes.isDefinition);

    return FieldDeclResult(type.get.primary.type, name, instance_usr, loc);
}

struct CxxBaseSpecifierResult {
    TypeKindAttr type;
    CppClassName name;
    CppNs[] reverseScope;
    USRType canonicalUSR;
    CppAccess access;
}

/** Analyze the node that represents a inheritance.
 *
 * reverseScope.
 *  scope the class reside in starting from the bottom.
 *  class A : public B {};
 *  reverseScope is then [B, A].
 *
 * canonicalUSR.
 * The resolved USR.
 * It is possible to inherit from for example a typedef. canonicalUSR would be
 * the class the typedef refers.
 */
auto analyzeCxxBaseSpecified(scope const CxxBaseSpecifier v, ref Container container, in uint indent) @safe {
    import clang.c.Index : CXCursorKind;
    import std.array : array;
    import std.algorithm : map;
    import cpptooling.data.type : CppAccess;
    import cpptooling.analyzer.clang.cursor_backtrack : backtrackScopeRange;
    import cpptooling.data : toStringDecl;

    auto type = () @trusted { return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppClassName(type.get.primary.type.toStringDecl);
    auto access = CppAccess(toAccessType(() @trusted { return v.cursor.access; }().accessSpecifier));
    auto usr = type.get.primary.type.kind.usr;

    type.get.primary.type.kind.info.match!((TypeKind.TypeRefInfo t) {
        usr = t.canonicalRef;
    }, (_) {});

    CppNs[] namespace;
    auto c_ref = v.cursor.referenced;
    if (c_ref.kind == CXCursorKind.noDeclFound) {
        namespace = backtrackScopeRange(c_ref).map!(a => CppNs(a.spelling)).array();
    } else {
        // TODO: remove this workaround.
        () @trusted {
            namespace = backtrackScopeRange(v.cursor).map!(a => CppNs(a.spelling)).array();
        }();
    }

    if (namespace.length > 0) {
        // namespace has the class itself in the range so must remove
        namespace = namespace[1 .. $];
    }

    return CxxBaseSpecifierResult(type.get.primary.type, name, namespace, usr, access);
}

struct RecordResult {
    TypeKindAttr type;
    CppClassName name;
    LocationTag location;
}

RecordResult analyzeRecord(T)(scope const T decl, ref Container container, in uint indent)
        if (staticIndexOf!(T, ClassDecl, StructDecl, ClassTemplate,
            ClassTemplatePartialSpecialization, UnionDecl) != -1) {
    return analyzeRecord(decl.cursor, container, indent);
}

RecordResult analyzeRecord(scope const Cursor cursor, ref Container container, in uint indent) @safe {
    auto type = () @trusted { return retrieveType(cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppClassName(cursor.spelling);

    return RecordResult(type.get.primary.type, name, type.get.primary.location);
}

///
struct TranslationUnitResult {
    string fileName;
}

auto analyzeTranslationUnit(scope const TranslationUnit tu, ref Container container, in uint indent) {
    auto fname = tu.cursor.spelling;
    return TranslationUnitResult(fname);
}

/** Reconstruct the semantic clang AST with dextool data structures suitable
 * for code generation.
 *
 * Note that it do NOT traverses the inheritance chain.
 */
final class ClassVisitor : Visitor {
    import clang.Cursor : Cursor;
    import libclang_ast.ast;
    import cpptooling.data;
    import cpptooling.data.symbol : Container;
    import libclang_ast.cursor_logger : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    /// The reconstructed class.
    CppClass root;

    private {
        Container* container;
        CppAccess accessType;
    }

    this(T)(const T decl, CppNsStack reside_in_ns, RecordResult result,
            ref Container container, const uint indent)
            if (is(T == ClassDecl) || is(T == StructDecl)) {
        this.container = &container;
        this.indent = indent;

        static if (is(T == StructDecl)) {
            this.accessType = CppAccess(AccessType.Public);
        } else {
            this.accessType = CppAccess(AccessType.Private);
        }

        this.root = CppClass(result.name, CppInherit[].init, reside_in_ns);
        this.root.usr = result.type.kind.usr;
    }

    override void visit(scope const(CxxBaseSpecifier) v) {
        import std.range : retro;
        import std.array : appender;
        import clang.c.Index : CXCursorKind;

        mixin(mixinNodeLog!());

        auto result = analyzeCxxBaseSpecified(v, *container, indent);
        auto inherit = CppInherit(result.name, result.access);
        inherit.usr = result.canonicalUSR;

        foreach (a; retro(result.reverseScope)) {
            inherit.put(a);
        }
        root.put(inherit);
    }

    override void visit(scope const(Constructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeConstructor(v, *container, indent);
        auto tor = CppCtor(result.type.kind.usr, result.name, result.params, accessType);
        root.put(tor);

        debug logger.trace("ctor: ", tor.toString);
    }

    override void visit(scope const(Destructor) v) @trusted {
        mixin(mixinNodeLog!());

        auto type = retrieveType(v.cursor, *container, indent);
        .put(type, *container, indent);

        auto result = analyzeDestructor(v, *container, indent);
        auto tor = CppDtor(result.type.kind.usr, result.name, accessType, classify(v.cursor));
        root.put(tor);

        debug logger.trace("dtor: ", tor.toString);
    }

    override void visit(scope const(CxxMethod) v) {
        import cpptooling.data : CppMethodOp;

        mixin(mixinNodeLog!());

        auto result = analyzeCxxMethod(v, *container, indent);

        if (result.isOperator) {
            auto op = CppMethodOp(result.type.kind.usr, result.name, result.params,
                    result.returnType, accessType,
                    CppConstMethod(result.isConst), result.virtualKind);
            root.put(op);
            debug logger.trace("operator: ", op.toString);
        } else {
            auto method = CppMethod(result.type.kind.usr, result.name, result.params,
                    result.returnType, accessType,
                    CppConstMethod(result.isConst), result.virtualKind);
            root.put(method);
            debug logger.trace("method: ", method.toString);
        }
    }

    override void visit(scope const(CxxAccessSpecifier) v) {
        mixin(mixinNodeLog!());

        accessType = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }

    override void visit(scope const(FieldDecl) v) {
        import cpptooling.data : TypeKindVariable;

        mixin(mixinNodeLog!());

        auto result = analyzeFieldDecl(v, *container, indent);
        root.put(TypeKindVariable(result.type, result.name), accessType);

        debug logger.trace("member: ", result.name);
    }
}
