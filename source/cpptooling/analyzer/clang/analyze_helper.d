/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.analyze_helper;

import logger = std.experimental.logger;

import std.typecons : Nullable;

import deimos.clang.index : CX_CXXAccessSpecifier;
import clang.SourceLocation : SourceLocation;

import cpptooling.analyzer.clang.ast : FunctionDecl, VarDecl;
import cpptooling.analyzer.clang.ast.visitor : Visitor;
import cpptooling.analyzer.clang.type : retrieveType, TypeKind, TypeKindAttr,
    TypeResult, logTypeResult;
import cpptooling.analyzer.clang.utility : put;
import cpptooling.data.type : AccessType, VariadicType, CxParam,
    TypeKindVariable, CppVariable, LocationTag, Location;
import cpptooling.data.representation : CFunction, CxGlobalVariable,
    CppMethodName;
import cpptooling.data.symbol.container : Container;

private AccessType toAccessType(CX_CXXAccessSpecifier accessSpec) {
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

private CxParam[] toCxParam(ref TypeResult tr, ref Container container) {
    import std.array;
    import std.algorithm : map;
    import std.range : chain, zip, tee;
    import std.string : strip;

    import cpptooling.analyzer.type;

    auto tr_params = tr.primary.kind.info.params;

    // dfmt off
    CxParam[] params = zip(// range 1
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
              })
        .array();
    // dfmt on

    return params;
}

private auto locToTag(SourceLocation c_loc) {
    auto l = c_loc.expansion();
    auto into = LocationTag(Location(l.file.name(), l.line, l.column));

    return into;
}

private bool isOperator(CppMethodName name_) {
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

Nullable!CFunction analyzeFunctionDecl(const(FunctionDecl) v, ref Container container, in uint indent) @trusted
out (result) {
    logger.info(!result.isNull, "function: ", result.get.toString);
}
body {
    import std.algorithm : among;
    import std.functional : pipe;

    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.type : TypeKind, retrieveType,
        logTypeResult;
    import cpptooling.analyzer.clang.utility : put;
    import cpptooling.data.type : TypeResult, TypeKindAttr;
    import cpptooling.data.representation : CxParam, CFunctionName,
        CxReturnType, CFunction, VariadicType, LocationTag, StorageClass;
    import cpptooling.data.symbol.container : Container;

    // hint, start reading the function from the bottom up.
    // design is pipe and data transformation

    Nullable!TypeResult extractAndStoreRawType(Cursor c) {
        auto tr = retrieveType(c, container, indent);
        if (tr.isNull) {
            return tr;
        }

        assert(tr.primary.kind.info.kind.among(TypeKind.Info.Kind.func,
                TypeKind.Info.Kind.typeRef, TypeKind.Info.Kind.simple));
        put(tr, container, indent);

        return tr;
    }

    Nullable!TypeResult lookupRefToConcreteType(Nullable!TypeResult tr) {
        if (tr.isNull) {
            return tr;
        }

        if (tr.primary.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            // replace typeRef kind with the func
            auto kind = container.find!TypeKind(tr.primary.kind.info.canonicalRef).front;
            tr.primary.kind = kind;
        }

        logTypeResult(tr, indent);
        assert(tr.primary.kind.info.kind == TypeKind.Info.Kind.func);

        return tr;
    }

    static struct ComposeData {
        TypeResult tr;
        CFunctionName name;
        LocationTag loc;
        VariadicType isVariadic;
        StorageClass storageClass;
    }

    ComposeData getCursorData(TypeResult tr) {
        import deimos.clang.index : CX_StorageClass;

        auto data = ComposeData(tr);

        data.name = CFunctionName(v.cursor.spelling);
        data.loc = locToTag(v.cursor.location());

        switch (v.cursor.storageClass()) with (CX_StorageClass) {
        case CX_SC_Extern:
            data.storageClass = StorageClass.Extern;
            break;
        case CX_SC_Static:
            data.storageClass = StorageClass.Static;
            break;
        default:
            break;
        }

        return data;
    }

    Nullable!CFunction composeFunc(ComposeData data) {
        Nullable!CFunction rval;

        auto return_type = container.find!TypeKind(data.tr.primary.kind.info.return_);
        if (auto return_type.length == 0) {
            return rval;
        }

        auto params = toCxParam(data.tr, container);

        VariadicType is_variadic;
        // according to C/C++ standard the last parameter is the only one
        // that can be a variadic, therefor only needing to peek at that
        // one.
        if (params.length > 0 && params[$ - 1].peek!VariadicType) {
            is_variadic = VariadicType.yes;
        }

        rval = CFunction(data.name, params, CxReturnType(TypeKindAttr(return_type.front,
                data.tr.primary.kind.info.returnAttr)), is_variadic, data.storageClass, data.loc);
        return rval;
    }

    // dfmt off
    auto rval = pipe!(extractAndStoreRawType,
                      lookupRefToConcreteType,
                      // either break early if null or continue composing a
                      // function representation
                      (Nullable!TypeResult tr) {
                          if (tr.isNull) {
                              return Nullable!CFunction();
                          } else {
                              return pipe!(getCursorData, composeFunc)(tr.get);
                          }
                      }
                      )
        (v.cursor);
    // dfmt on

    return rval;
}

CxGlobalVariable analyzeVarDecl(const(VarDecl) v, ref Container container, in uint indent)
out (result) {
    logger.info("variable:", result.toString);
}
body {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.type : retrieveType;
    import cpptooling.analyzer.clang.utility : put;
    import cpptooling.data.representation : CppVariable;

    Cursor c = v.cursor;
    auto type = retrieveType(c, container, indent);
    put(type, container, indent);

    auto name = CppVariable(v.cursor.spelling);
    auto loc = locToTag(v.cursor.location());

    return CxGlobalVariable(type.primary, name, loc);
}

/**
 * Note that it also traverses the inheritance chain.
 */
final class ClassVisitor : Visitor {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.ast.visitor;
    import cpptooling.data.representation;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    Container* container;
    CppClass root;
    CppAccess accessType;

    this(const(ClassDecl) decl, const(CppNsStack) reside_in_ns,
            ref Container container, in uint indent) {
        this.container = &container;
        this.indent = indent;
        this.accessType = CppAccess(AccessType.Private);

        this.root = () @trusted{
            // BUG location should be the definition. This may result in the
            // declaration.
            auto loc = locToTag(decl.cursor.location());
            auto name = CppClassName(decl.cursor.spelling);
            return CppClass(name, loc, CppInherit[].init, reside_in_ns);
        }();

        Cursor c = decl.cursor;
        auto type = retrieveType(c, container, indent);
        put(type, container, indent);
        this.root.usr = type.primary.kind.usr;
    }

    override void visit(const(CXXBaseSpecifier) v) @trusted {
        import std.algorithm : each;
        import std.range : retro;
        import std.array : appender;
        import deimos.clang.index : CXCursorKind;

        mixin(mixinNodeLog!());

        auto c_ref = v.cursor.referenced;
        auto name = CppClassName(c_ref.spelling);
        auto access = CppAccess(toAccessType(c_ref.access.accessSpecifier));
        auto inherit = CppInherit(name, access);

        // backtrack to determine the class scope.
        auto namespace = appender!(CppNs[])();
        Cursor curr = c_ref;
        while (curr.isValid) {
            if (curr.kind == CXCursorKind.CXCursor_Namespace) {
                namespace.put(CppNs(curr.spelling));
            }

            curr = curr.semanticParent;
        }

        retro(namespace.data).each!(a => inherit.put(a));

        auto rt = retrieveType(c_ref, *container, indent);
        put(rt, *container, indent);

        if (rt.primary.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            inherit.usr = cast(USRType) rt.primary.kind.info.canonicalRef;
        } else {
            inherit.usr = cast(USRType) rt.primary.kind.usr;
        }

        root.put(inherit);
    }

    override void visit(const(Constructor) v) @trusted {
        mixin(mixinNodeLog!());

        Cursor c = v.cursor;
        auto type = retrieveType(c, *container, indent);
        put(type, *container, indent);

        auto params = toCxParam(type, *container);
        auto name = CppMethodName(v.cursor.spelling);
        auto tor = CppCtor(name, params, accessType);
        root.put(tor);

        logger.trace("ctor: ", tor.toString);
    }

    override void visit(const(Destructor) v) @trusted {
        mixin(mixinNodeLog!());

        Cursor c_ = v.cursor;
        auto type = retrieveType(c_, *container, indent);
        .put(type, *container, indent);

        auto name = CppMethodName(v.cursor.spelling);
        auto tor = CppDtor(name, accessType, classify(v.cursor));
        root.put(tor);

        logger.trace("dtor: ", tor.toString);
    }

    override void visit(const(CXXMethod) v) @trusted {
        import cpptooling.data.representation : CppMethodOp;

        mixin(mixinNodeLog!());

        Cursor c = v.cursor;
        auto type = retrieveType(c, *container, indent);
        assert(type.get.primary.kind.info.kind == TypeKind.Info.Kind.func);
        put(type, *container, indent);

        auto params = toCxParam(type, *container);
        auto name = CppMethodName(c.spelling);
        auto return_type = CxReturnType(TypeKindAttr(container.find!TypeKind(
                type.primary.kind.info.return_).front, type.primary.kind.info.returnAttr));
        auto is_virtual = classify(c);

        if (name.isOperator) {
            auto op = CppMethodOp(name, params, return_type, accessType,
                    CppConstMethod(type.primary.attr.isConst), is_virtual);
            root.put(op);
            logger.trace("operator: ", op.toString);
        } else {
            auto method = CppMethod(name, params, return_type, accessType,
                    CppConstMethod(type.primary.attr.isConst), is_virtual);
            root.put(method);
            logger.trace("method: ", method.toString);
        }
    }

    override void visit(const(CXXAccessSpecifier) v) @trusted {
        mixin(mixinNodeLog!());

        accessType = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }

    override void visit(const(FieldDecl) v) @trusted {
        import std.typecons : TypedefType;
        import cpptooling.data.representation : TypeKindVariable;

        mixin(mixinNodeLog!());

        Cursor c = v.cursor;
        auto type = retrieveType(c, *container, indent);
        put(type, *container, indent);

        auto name = CppVariable(v.cursor.spelling);
        root.put(TypeKindVariable(type.primary, name), cast(TypedefType!CppAccess) accessType);

        logger.trace("member: ", name);
    }

    override void visit(const(ClassDecl) v) @trusted {
        import std.typecons : TypedefType, scoped;

        mixin(mixinNodeLog!());
        logger.info("class: ", v.cursor.spelling);

        if (v.cursor.isDefinition) {
            auto visitor = scoped!ClassVisitor(v, root.resideInNs, *container, indent + 1);
            v.accept(visitor);
            root.put(visitor.root, cast(TypedefType!CppAccess) accessType);
            container.put(visitor.root, visitor.root.fullyQualifiedName);
        } else {
            Cursor c = v.cursor;
            auto type = retrieveType(c, *container, indent);
            put(type, *container, indent);
        }
    }

    private static CppVirtualMethod classify(T)(T c) {
        auto is_virtual = MemberVirtualType.Normal;
        if (c.func.isPureVirtual) {
            is_virtual = MemberVirtualType.Pure;
        } else if (c.func.isVirtual) {
            is_virtual = MemberVirtualType.Virtual;
        }

        return CppVirtualMethod(is_virtual);
    }
}
