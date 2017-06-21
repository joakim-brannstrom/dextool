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

import std.traits : Unqual;
import std.typecons : Nullable, tuple, Flag, Yes, No;
import std.meta : staticIndexOf;

import deimos.clang.index : CX_CXXAccessSpecifier, CX_StorageClass,
    CXLanguageKind;
import clang.Cursor : Cursor;
import clang.SourceLocation : SourceLocation;

import cpptooling.analyzer.clang.ast : ClassTemplate,
    ClassTemplatePartialSpecialization, Constructor, CXXMethod, ClassDecl,
    CXXBaseSpecifier, Destructor, FieldDecl, FunctionDecl, StructDecl,
    TranslationUnit, UnionDecl, VarDecl, Visitor;
import cpptooling.analyzer.clang.type : retrieveType, TypeKind, TypeKindAttr,
    TypeResult, TypeResults, logTypeResult;
import cpptooling.analyzer.clang.store : put;
import cpptooling.data.type : AccessType, VariadicType, CxParam,
    TypeKindVariable, CppVariable, LocationTag, Location, CxReturnType,
    CppVirtualMethod, CppMethodName, CppClassName, CppNs, USRType, CppAccess,
    StorageClass, CFunctionName, Language;
import cpptooling.data.representation : CFunction, CxGlobalVariable;
import cpptooling.data.symbol.container : Container;

/// Convert Cursor attributes to enum representation.
private CppVirtualMethod classify(T)(T c) @safe if (is(Unqual!T == Cursor)) {
    import cpptooling.data.type : MemberVirtualType;

    auto is_virtual = MemberVirtualType.Normal;
    auto func = () @trusted{ return c.func; }();

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
    case CX_CXXInvalidAccessSpecifier:
        return AccessType.Public;
    case CX_CXXPublic:
        return AccessType.Public;
    case CX_CXXProtected:
        return AccessType.Protected;
    case CX_CXXPrivate:
        return AccessType.Private;
    }
}

StorageClass toStorageClass(CX_StorageClass storageClass) @safe pure nothrow @nogc {
    switch (storageClass) with (CX_StorageClass) {
    case CX_SC_Extern:
        return StorageClass.Extern;
    case CX_SC_Static:
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

    import cpptooling.analyzer.type;

    auto tr_params = kind.info.params;

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
                  return CxParam(TypeKindAttr(a[0], a[1].attr));
              } else {
                  return CxParam(TypeKindVariable(TypeKindAttr(a[0], a[1].attr), CppVariable(a[1].id)));
              }
              });
    // dfmt on

    return () @trusted{ return params.array(); }();
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
body {
    import std.algorithm : canFind;

    // assuming that the C++ USR always contains a '#'.
    if (c.usr.canFind('#')) {
        return Language.cpp;
    }

    final switch (c.language) with (CXLanguageKind) {
    case CXLanguage_Invalid:
        return Language.unknown;
    case CXLanguage_C:
        return Language.c;
    case CXLanguage_ObjC:
        return Language.unknown;
    case CXLanguage_CPlusPlus:
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

FunctionDeclResult analyzeFunctionDecl(const(FunctionDecl) v, ref Container container, in uint indent) @safe {
    return analyzeFunctionDecl(v.cursor, container, indent);
}

FunctionDeclResult analyzeFunctionDecl(const(Cursor) c_in, ref Container container, in uint indent) @safe
in {
    import deimos.clang.index : CXCursorKind;

    assert(c_in.kind == CXCursorKind.CXCursor_FunctionDecl);
}
body {
    import std.algorithm : among;
    import std.functional : pipe;

    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.type : TypeKind, retrieveType,
        logTypeResult;
    import cpptooling.data.type : TypeResult, TypeKindAttr;
    import cpptooling.data.representation : CxParam, CFunctionName,
        CxReturnType, CFunction, VariadicType, LocationTag, StorageClass;
    import cpptooling.data.symbol.container : Container;

    // hint, start reading the function from the bottom up.
    // design is pipe and data transformation

    Nullable!TypeResults extractAndStoreRawType(const(Cursor) c) @safe {
        auto tr = () @trusted{ return retrieveType(c, container, indent); }();
        if (tr.isNull) {
            return tr;
        }

        assert(tr.primary.type.kind.info.kind.among(TypeKind.Info.Kind.func,
                TypeKind.Info.Kind.typeRef, TypeKind.Info.Kind.simple));
        put(tr, container, indent);

        return tr;
    }

    Nullable!TypeResults lookupRefToConcreteType(Nullable!TypeResults tr) @safe {
        if (tr.isNull) {
            return tr;
        }

        if (tr.primary.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            // replace typeRef kind with the func
            auto kind = container.find!TypeKind(tr.primary.type.kind.info.canonicalRef).front;
            tr.primary.type.kind = kind;
        }

        logTypeResult(tr, indent);
        assert(tr.primary.type.kind.info.kind == TypeKind.Info.Kind.func);

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

    ComposeData getCursorData(TypeResults tr) @safe {
        auto data = ComposeData(tr);

        data.name = CFunctionName(c_in.spelling);
        data.loc = locToTag(c_in.location());
        data.is_definition = cast(Flag!"isDefinition") c_in.isDefinition;
        data.storageClass = c_in.storageClass().toStorageClass;
        data.language = c_in.toLanguage;

        return data;
    }

    FunctionDeclResult composeFunc(ComposeData data) @safe {
        Nullable!CFunction rval;

        auto return_type = container.find!TypeKind(data.tr.primary.type.kind.info.return_);
        if (return_type.length == 0) {
            return FunctionDeclResult.init;
        }

        auto params = toCxParam(data.tr.primary.type.kind, container);

        VariadicType is_variadic;
        // according to C/C++ standard the last parameter is the only one
        // that can be a variadic, therefor only needing to peek at that
        // one.
        if (params.length > 0) {
            is_variadic = cast(VariadicType)() @trusted{
                return params[$ - 1].peek!VariadicType;
            }();
        }

        return FunctionDeclResult(Yes.isValid, data.tr.primary.type, data.name,
                TypeKindAttr(return_type.front, data.tr.primary.type.kind.info.returnAttr), is_variadic,
                data.storageClass, params, data.loc, data.is_definition, data.language);
    }

    // dfmt off
    auto rval = pipe!(extractAndStoreRawType,
                      lookupRefToConcreteType,
                      // either break early if null or continue composing a
                      // function representation
                      (Nullable!TypeResults tr) {
                          if (tr.isNull) {
                              return FunctionDeclResult.init;
                          } else {
                              return pipe!(getCursorData, composeFunc)(tr.get);
                          }
                      }
                      )
        (c_in);
    // dfmt on

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
VarDeclResult analyzeVarDecl(const(VarDecl) v, ref Container container, in uint indent) @safe {
    return analyzeVarDecl(v.cursor, container, indent);
}

/// ditto
VarDeclResult analyzeVarDecl(const(Cursor) v, ref Container container, in uint indent) @safe
in {
    import deimos.clang.index : CXCursorKind;

    assert(v.kind == CXCursorKind.CXCursor_VarDecl);
}
body {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.type : retrieveType;
    import cpptooling.data.representation : CppVariable;

    auto type = () @trusted{ return retrieveType(v, container, indent); }();
    put(type, container, indent);

    auto name = CppVariable(v.spelling);
    auto loc = locToTag(v.location());
    auto instance_usr = USRType(v.usr);
    // Assuming that all variable declarations have a USR
    assert(instance_usr.length > 0);

    // store the location to enable creating relations to/from this instance
    // USR.
    container.put(loc, instance_usr, Yes.isDefinition);

    auto storage = () @trusted{ return v.storageClass.toStorageClass; }();

    return VarDeclResult(type.primary.type, name, loc, instance_usr, storage);
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
auto analyzeConstructor(const(Constructor) v, ref Container container, in uint indent) @safe {
    auto type = () @trusted{ return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto params = toCxParam(type.primary.type.kind, container);
    auto name = CppMethodName(v.cursor.spelling);

    return ConstructorResult(type.primary.type, name, params, type.primary.location);
}

struct DestructorResult {
    TypeKindAttr type;
    CppMethodName name;
    CppVirtualMethod virtualKind;
    LocationTag location;
}

/// ditto
auto analyzeDestructor(const(Destructor) v, ref Container container, in uint indent) @safe {
    auto type = () @trusted{ return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppMethodName(v.cursor.spelling);
    auto virtual_kind = classify(v.cursor);

    return DestructorResult(type.primary.type, name, virtual_kind, type.primary.location);
}

struct CXXMethodResult {
    TypeKindAttr type;
    CppMethodName name;
    CxParam[] params;
    Flag!"isOperator" isOperator;
    CxReturnType returnType;
    CppVirtualMethod virtualKind;
    Flag!"isConst" isConst;
    LocationTag location;
}

CXXMethodResult analyzeCXXMethod(const(CXXMethod) v, ref Container container, in uint indent) @safe {
    return analyzeCXXMethod(v.cursor, container, indent);
}

/// ditto
CXXMethodResult analyzeCXXMethod(const(Cursor) v, ref Container container, in uint indent) @safe {
    auto type = () @trusted{ return retrieveType(v, container, indent); }();
    assert(type.get.primary.type.kind.info.kind == TypeKind.Info.Kind.func);
    put(type, container, indent);

    auto name = CppMethodName(v.spelling);
    auto params = toCxParam(type.primary.type.kind, container);
    auto return_type = CxReturnType(TypeKindAttr(container.find!TypeKind(
            type.primary.type.kind.info.return_).front, type.primary.type.kind.info.returnAttr));
    auto is_virtual = classify(v);

    return CXXMethodResult(type.primary.type, name, params,
            cast(Flag!"isOperator") isOperator(name), return_type, is_virtual,
            cast(Flag!"isConst") type.primary.type.attr.isConst, type.primary.location);
}

struct FieldDeclResult {
    TypeKindAttr type;
    CppVariable name;
    USRType instanceUSR;
    LocationTag location;
}

/// ditto
auto analyzeFieldDecl(const(FieldDecl) v, ref Container container, in uint indent) @safe {
    import cpptooling.analyzer.clang.type : makeEnsuredUSR;

    auto type = () @trusted{ return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppVariable(v.cursor.spelling);

    auto instance_usr = makeEnsuredUSR(v.cursor, indent + 1);
    // Assuming that all field declarations have a USR
    assert(instance_usr.length > 0);

    auto loc = () @trusted{ return locToTag(v.cursor.location()); }();
    // store the location to enable creating relations to/from this instance
    // USR.
    container.put(loc, instance_usr, Yes.isDefinition);

    return FieldDeclResult(type.primary.type, name, instance_usr, loc);
}

struct CXXBaseSpecifierResult {
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
auto analyzeCXXBaseSpecified(const(CXXBaseSpecifier) v, ref Container container, in uint indent) @safe {
    import deimos.clang.index : CXCursorKind;
    import std.array : array;
    import std.algorithm : map;
    import cpptooling.data.type : CppAccess;
    import cpptooling.analyzer.clang.cursor_backtrack : backtrackScopeRange;
    import cpptooling.analyzer.type : toStringDecl;

    auto type = () @trusted{ return retrieveType(v.cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppClassName(type.primary.type.toStringDecl);
    auto access = CppAccess(toAccessType(() @trusted{ return v.cursor.access; }().accessSpecifier));
    auto usr = type.primary.type.kind.usr;

    if (type.primary.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
        usr = type.primary.type.kind.info.canonicalRef;
    }

    CppNs[] namespace;
    auto c_ref = v.cursor.referenced;
    if (c_ref.kind == CXCursorKind.CXCursor_NoDeclFound) {
        namespace = backtrackScopeRange(c_ref).map!(a => CppNs(a.spelling)).array();
    } else {
        namespace = backtrackScopeRange(v.cursor).map!(a => CppNs(a.spelling)).array();
    }

    if (namespace.length > 0) {
        // namespace has the class itself in the range so must remove
        namespace = namespace[1 .. $];
    }

    return CXXBaseSpecifierResult(type.primary.type, name, namespace, usr, access);
}

struct RecordResult {
    TypeKindAttr type;
    CppClassName name;
    LocationTag location;
}

RecordResult analyzeRecord(T)(const(T) decl, ref Container container, in uint indent)
        if (staticIndexOf!(T, ClassDecl, StructDecl, ClassTemplate,
            ClassTemplatePartialSpecialization, UnionDecl) != -1) {
    return analyzeRecord(decl.cursor, container, indent);
}

RecordResult analyzeRecord(const(Cursor) cursor, ref Container container, in uint indent) @safe {
    auto type = () @trusted{ return retrieveType(cursor, container, indent); }();
    put(type, container, indent);

    auto name = CppClassName(cursor.spelling);

    return RecordResult(type.primary.type, name, type.primary.location);
}

///
struct TranslationUnitResult {
    string fileName;
}

auto analyzeTranslationUnit(const(TranslationUnit) tu, ref Container container, in uint indent) {
    auto fname = tu.spelling;
    return TranslationUnitResult(fname);
}

/** Reconstruct the semantic clang AST with dextool data structures suitable
 * for code generation.
 *
 * Note that it do NOT traverses the inheritance chain.
 */
final class ClassVisitor : Visitor {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.data.representation;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    /// The reconstructed class.
    CppClass root;

    private {
        Container* container;
        CppAccess accessType;
    }

    this(const(ClassDecl) decl, const(CppNsStack) reside_in_ns,
            ref Container container, in uint indent) {
        this.container = &container;
        this.indent = indent;
        this.accessType = CppAccess(AccessType.Private);

        auto result = analyzeRecord(decl, container, indent);
        this.root = CppClass(result.name, CppInherit[].init, reside_in_ns);
        this.root.usr = result.type.kind.usr;
    }

    override void visit(const(CXXBaseSpecifier) v) {
        import std.range : retro;
        import std.array : appender;
        import deimos.clang.index : CXCursorKind;

        mixin(mixinNodeLog!());

        auto result = analyzeCXXBaseSpecified(v, *container, indent);
        auto inherit = CppInherit(result.name, result.access);
        inherit.usr = result.canonicalUSR;

        foreach (a; retro(result.reverseScope)) {
            inherit.put(a);
        }
        root.put(inherit);
    }

    override void visit(const(Constructor) v) @trusted {
        mixin(mixinNodeLog!());

        auto result = analyzeConstructor(v, *container, indent);
        auto tor = CppCtor(result.type.kind.usr, result.name, result.params, accessType);
        root.put(tor);

        logger.trace("ctor: ", tor.toString);
    }

    override void visit(const(Destructor) v) @trusted {
        mixin(mixinNodeLog!());

        auto type = retrieveType(v.cursor, *container, indent);
        .put(type, *container, indent);

        auto result = analyzeDestructor(v, *container, indent);
        auto tor = CppDtor(result.type.kind.usr, result.name, accessType, classify(v.cursor));
        root.put(tor);

        logger.trace("dtor: ", tor.toString);
    }

    override void visit(const(CXXMethod) v) @trusted {
        import cpptooling.data.representation : CppMethodOp;

        mixin(mixinNodeLog!());

        auto result = analyzeCXXMethod(v, *container, indent);

        if (result.isOperator) {
            auto op = CppMethodOp(result.type.kind.usr, result.name, result.params,
                    result.returnType, accessType,
                    CppConstMethod(result.isConst), result.virtualKind);
            root.put(op);
            logger.trace("operator: ", op.toString);
        } else {
            auto method = CppMethod(result.type.kind.usr, result.name, result.params,
                    result.returnType, accessType,
                    CppConstMethod(result.isConst), result.virtualKind);
            root.put(method);
            logger.trace("method: ", method.toString);
        }
    }

    override void visit(const(CXXAccessSpecifier) v) @trusted {
        mixin(mixinNodeLog!());

        accessType = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }

    override void visit(const(FieldDecl) v) @trusted {
        import cpptooling.data.representation : TypeKindVariable;

        mixin(mixinNodeLog!());

        auto result = analyzeFieldDecl(v, *container, indent);
        root.put(TypeKindVariable(result.type, result.name), accessType);

        logger.trace("member: ", cast(string) result.name);
    }
}
