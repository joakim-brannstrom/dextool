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

import deimos.clang.index : CXCursorKind, CX_CXXAccessSpecifier;
import clang.Cursor : Cursor;
import clang.SourceLocation : SourceLocation;

import cpptooling.analyzer.clang.ast : FunctionDecl, VarDecl;
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

// Store the derived type information
// TODO remove
private void put(ref Cursor c, ref Container container) {
    switch (c.kind) with (CXCursorKind) {
    case CXCursor_CXXAccessSpecifier:
    case CXCursor_CXXBaseSpecifier:
    case CXCursor_MemberRef:
    case CXCursor_NamespaceRef:
    case CXCursor_LabelRef:
    case CXCursor_TemplateRef:
    case CXCursor_TypeRef:
        // do nothing
        return;

    default:
        break;
    }

    auto tka = retrieveType(c, container);
    if (!tka.isNull) {
        logTypeResult(tka);
        container.put(tka.primary.kind);
        foreach (e; tka.extra) {
            container.put(e.kind);
        }
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

private auto toInternal(SourceLocation c_loc) {
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
        data.loc = toInternal(v.cursor.location());

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
    auto loc = toInternal(v.cursor.location());

    return CxGlobalVariable(type.primary, name, loc);
}

/** Extract information about a class.
 *
 * TODO make a proper visitor for the class analyze
 */
struct ClassVisitor {
    import clang.SourceLocation;
    import cpptooling.data.representation : CppClassName, CppClassVirtual,
        CppClass, LocationTag, ClassVirtualType, CppNsStack, CppInherit;
    import cpptooling.data.symbol.container;
    import cpptooling.data.symbol.types : USRType;

    /** Make a ClassVisitor to descend a Clang Cursor.
     *
     * Static make to create ClassVisitor objects to avoid the unnecessary storage
     * of a Cursor but still derive parameters from the Cursor.
     */
    static auto make(ref Cursor c, CppNsStack reside_in_ns)
    in {
        assert(c.kind == CXCursorKind.CXCursor_ClassDecl);
    }
    body {
        auto loc = toInternal(c.location());
        auto name = CppClassName(c.spelling);
        auto r = ClassVisitor(name, loc, reside_in_ns);
        logger.info("class: ", cast(string) name);
        return r;
    }

    /// The constructor is disabled to force the class to be in a consistent state.
    @disable this();

    //TODO consider making it public. The reason for private is dubious.
    private this(CppClassName name, LocationTag loc, CppNsStack reside_in_ns) {
        this.data = CppClass(name, loc, CppInherit[].init, reside_in_ns);
    }

    auto visit(ref Cursor c, ref Container container)
    in {
        assert(c.kind == CXCursorKind.CXCursor_ClassDecl);
    }
    body {
        auto d = Nullable!CppClass(data);
        d.nullify;

        auto type = retrieveType(c, container);
        put(type, container);

        ///TODO add information if it is a public/protected/private class.
        ///TODO add metadata to the class if it is a definition or declaration
        if (!c.isDefinition) {
            logger.trace("Forward declaration of class ", c.location.toString);
            return d;
        }

        d = ClassDescendVisitor(data).visit(c, container);
        d.usr = cast(USRType) type.primary.kind.usr;
        return d;
    }

private:
    CppClass data;
}

/** Descend a class cursor to extract interior information.
 * C'tors, d'tors, member methods etc.
 * Cleanly separates the functionality for initializing the container for a
 * class and the analyze logic.
 *
 * Note that it also traverses the inheritance chain.
 *
 * TODO make a proper visitor for the class analyze
 */
struct ClassDescendVisitor {
    import cpptooling.data.representation;
    import cpptooling.data.symbol.container;
    import cpptooling.utility.clang : visitAst, logNode;

    @disable this();

    this(CppClass data) {
        this.data = data;
        this.accessType = CppAccess(AccessType.Private);
    }

    /** Visit node c and children extracting data for the class.
     *
     * c must be a class cursor.
     *
     * Params:
     *  c = cursor to visit.
     *  container = stored nested classes in the container.
     */
    CppClass visit(ref Cursor c, ref Container container)
    in {
        assert(c.kind == CXCursorKind.CXCursor_ClassDecl);
    }
    body {
        this.container = &container;

        visitAst!(typeof(this))(c, this);
        return data;
    }

    void applyRoot(ref Cursor root) {
        logNode(root, 0);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        import std.typecons : TypedefType;

        logNode(c, 0);
        put(c, *container);

        bool descend = true;

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_Constructor:
            applyConstructor(c, parent);
            descend = false;
            break;
        case CXCursor_Destructor:
            applyDestructor(c, parent);
            descend = false;
            break;
        case CXCursor_CXXMethod:
            applyMethod(c, parent);
            descend = false;
            break;
        case CXCursor_CXXAccessSpecifier:
            accessType = CppAccess(toAccessType(c.access.accessSpecifier));
            break;
        case CXCursor_CXXBaseSpecifier:
            applyInherit(c, parent);
            descend = false;
            break;
        case CXCursor_FieldDecl:
            applyField(c, accessType);
            descend = false;
            break;
        case CXCursor_ClassDecl:
            // Another visitor must analyze the nested class to allow us to
            // construct a correct representation.
            // TODO hmm a CppNsStack may not be foolproof. Investigate if it is
            // needed to use a nesting structure that also describe the class
            // it reside in.
            // TODO change accessType from CppAccess to see if it reduces the
            // casts
            auto class_ = ClassVisitor.make(c, data.resideInNs.dup).visit(c, *container);
            if (!class_.isNull) {
                data.put(class_.get, cast(TypedefType!CppAccess) accessType);
                container.put(class_, class_.fullyQualifiedName);
            }
            descend = false;
            break;
        default:
            break;
        }

        return descend;
    }

private:
    static CppVirtualMethod classify(T)(T c) {
        auto is_virtual = MemberVirtualType.Normal;
        if (c.func.isPureVirtual) {
            is_virtual = MemberVirtualType.Pure;
        } else if (c.func.isVirtual) {
            is_virtual = MemberVirtualType.Virtual;
        }

        return CppVirtualMethod(is_virtual);
    }

    void applyConstructor(ref Cursor c, ref Cursor parent) {
        auto tka = retrieveType(c, *container);
        put(tka, *container);

        auto params = toCxParam(tka, *container);
        auto name = CppMethodName(c.spelling);
        auto tor = CppCtor(name, params, accessType);
        logger.info("ctor: ", tor.toString);
        data.put(tor);
    }

    void applyDestructor(ref Cursor c, ref Cursor parent) {
        auto name = CppMethodName(c.spelling);
        auto tor = CppDtor(name, accessType, classify(c));
        logger.info("dtor: ", tor.toString);
        data.put(tor);
    }

    void applyInherit(ref Cursor c, ref Cursor parent) {
        auto inherit = InheritVisitor.make(c).visit(c, *container);
        data.put(inherit);
    }

    void applyField(ref Cursor c, const CppAccess accessType) {
        import std.typecons : TypedefType;
        import cpptooling.data.representation : TypeKindVariable;

        auto tka = retrieveType(c, *container);
        auto name = CppVariable(c.spelling);

        data.put(TypeKindVariable(tka.primary, name), cast(TypedefType!CppAccess) accessType);
    }

    void applyMethod(ref Cursor c, ref Cursor parent) {
        import cpptooling.data.representation : CppMethodOp;

        auto tr = retrieveType(c, *container);
        assert(tr.get.primary.kind.info.kind == TypeKind.Info.Kind.func);
        put(tr, *container);

        auto params = toCxParam(tr, *container);
        auto name = CppMethodName(c.spelling);
        auto return_type = CxReturnType(TypeKindAttr(container.find!TypeKind(
                tr.primary.kind.info.return_).front, tr.primary.kind.info.returnAttr));
        auto is_virtual = classify(c);

        if (isOperator(name)) {
            auto op = CppMethodOp(name, params, return_type, accessType,
                    CppConstMethod(tr.primary.attr.isConst), is_virtual);
            logger.info("operator: ", op.toString);
            data.put(op);
        } else {
            auto method = CppMethod(name, params, return_type, accessType,
                    CppConstMethod(tr.primary.attr.isConst), is_virtual);
            logger.info("method: ", method.toString);
            data.put(method);
        }
    }

private:
    CppClass data;
    CppAccess accessType;
    Container* container;
}

/** Extract information regarding a class inheritance.
 *
 * TODO make a proper visitor for the class analyze
 */
struct InheritVisitor {
    import cpptooling.data.representation;
    import cpptooling.utility.stack : VisitNodeDepth;
    import cpptooling.utility.clang : logNode;
    import cpptooling.data.symbol.types : USRType;

    static auto make(ref Cursor c)
    in {
        assert(c.kind == CXCursorKind.CXCursor_CXXBaseSpecifier);
        assert(c.isReference);
    }
    body {
        // name of a CXXBaseSpecificer is "class X" while referenced is "X"
        auto name = CppClassName(c.referenced.spelling);
        auto access = CppAccess(toAccessType(c.access.accessSpecifier));
        auto inherit = CppInherit(name, access);

        auto r = InheritVisitor(inherit);

        return r;
    }

    auto visit(ref Cursor c, ref Container container)
    in {
        assert(c.isReference);
    }
    body {
        static struct GatherNs {
            Container* container;
            CppNsStack stack;

            void apply(ref Cursor c, int depth)
            in {
                assert(c.kind == CXCursorKind.CXCursor_Namespace);
            }
            body {
                logNode(c, depth);
                stack ~= CppNs(c.spelling);
            }
        }

        auto c_ref = c.referenced;
        auto gather = GatherNs(&container);
        backtrackNode!(kind => kind == CXCursorKind.CXCursor_Namespace)(c_ref,
                gather, "cxx_base -> ns", 1);

        import std.algorithm : each;
        import std.range : retro;

        //TODO would copy work instead of each?
        retro(gather.stack).each!(a => data.put(a));

        auto rt = retrieveType(c_ref, container);
        put(rt, container);
        if (rt.primary.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            data.usr = cast(USRType) rt.primary.kind.info.canonicalRef;
        } else {
            data.usr = cast(USRType) rt.primary.kind.usr;
        }

        return data;
    }

    // TODO is backtracker useful in other places? moved to allow it to be
    // reused
    static void backtrackNode(alias pred = a => true, T)(ref Cursor c,
            ref T callback, string log_txt, int depth) {
        import std.range : repeat;

        auto curr = c;
        while (curr.isValid) {
            bool matching = pred(curr.kind);
            logger.trace(repeat(' ', depth), "|", matching ? "ok|" : "no|", log_txt);

            if (matching) {
                callback.apply(curr, depth);
            }

            curr = curr.semanticParent;
            ++depth;
        }
    }

private:
    CppInherit data;
}
