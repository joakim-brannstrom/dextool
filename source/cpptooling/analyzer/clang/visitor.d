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
module cpptooling.analyzer.clang.visitor;

import std.conv : to;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Cursor;
import clang.SourceLocation;

import cpptooling.data.representation : AccessType;
import cpptooling.utility.clang : visitAst, logNode;

auto toInternal(T)(SourceLocation c_loc) {
    import std.conv : text;

    T into;
    auto l = c_loc.expansion();

    into.file = l.file.name();
    into.line = l.line;
    into.column = l.column;

    return into;
}

/// Seems more complicated than it need to be but the goal is to keep the
/// API the same.
struct FunctionVisitor {
    import cpptooling.data.representation : CxParam, CFunctionName,
        CxReturnType, CFunction, VariadicType, CxLocation;

    static auto make(ref Cursor) {
        return typeof(this)();
    }

    auto visit(ref Cursor c) {
        import translator.Type : TypeKind, translateType;

        auto params = paramDeclTo(c);
        auto name = CFunctionName(c.spelling);
        auto return_type = CxReturnType(translateType(c.func.resultType));
        auto is_variadic = c.func.isVariadic ? VariadicType.yes : VariadicType.no;
        auto loc = toInternal!CxLocation(c.location());

        auto func = CFunction(name, params, return_type, is_variadic, loc);
        logger.info("function: ", func.toString);

        return func;
    }
}

/** Descend a class cursor to extract interior information.
 * C'tors, d'tors, member methods etc.
 * Cleanly separates the functionality for initializing the container for a
 * class and the analyze logic.
 *
 * Note that it also traverses the inheritance chain.
 */
struct ClassDescendVisitor {
    import cpptooling.data.representation : CppClass, CppAccess, CxParam,
        CppMethodName, CppCtor, CppDtor, CppVirtualMethod, VirtualType,
        CxReturnType, CppMethod, CppConstMethod;

    @disable this();

    this(CppClass data) {
        //if (data.isNull) {
        //    logger.fatal("CppClass parameter is null");
        //    throw new Exception("CppClass parameter is null");
        //}
        this.data = data;
        this.accessType = CppAccess(AccessType.Private);
    }

    CppClass visit(ref Cursor c) {
        visitAst!(typeof(this))(c, this);
        return data;
    }

    void applyRoot(ref Cursor root) {
        logNode(root, 0);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        import std.typecons : TypedefType;

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
            break;
        case CXCursor_ClassDecl:
            // Another visitor must analyze the nested class to allow us to
            // construct a correct representation.
            data.put(ClassVisitor.make(c).visit(c), cast(TypedefType!CppAccess) accessType);
            descend = false;
            break;
        default:
            break;
        }
        return descend;
    }

private:
    void applyConstructor(ref Cursor c, ref Cursor parent) {
        auto params = paramDeclTo(c);
        auto name = CppMethodName(c.spelling);
        auto tor = CppCtor(name, params, accessType);
        logger.info("ctor: ", tor.toString);
        data.put(tor);
    }

    void applyDestructor(ref Cursor c, ref Cursor parent) {
        auto name = CppMethodName(c.spelling);
        auto tor = CppDtor(name, accessType,
            CppVirtualMethod(c.func.isVirtual ? VirtualType.Yes : VirtualType.No));
        logger.info("dtor: ", tor.toString);
        data.put(tor);
    }

    void applyMethod(ref Cursor c, ref Cursor parent) {
        import translator.Type : TypeKind, translateType;

        auto params = paramDeclTo(c);
        auto name = CppMethodName(c.spelling);
        auto return_type = CxReturnType(translateType(c.func.resultType));

        auto is_virtual = CppVirtualMethod(VirtualType.No);
        if (c.func.isPureVirtual) {
            is_virtual = CppVirtualMethod(VirtualType.Pure);
        } else if (c.func.isVirtual) {
            is_virtual = CppVirtualMethod(VirtualType.Yes);
        }

        auto method = CppMethod(name, params, return_type, accessType,
            CppConstMethod(c.func.isConst), is_virtual);
        logger.info("method: ", method.toString);
        data.put(method);
    }

private:
    CppClass data;
    CppAccess accessType;
}

/** Extract information about a class.
 *
 * The constructor is disabled to force the class to be in a consistent state.
 * static make to create ClassVisitor objects to avoid the unnecessary storage
 * of a Cursor but still derive parameters from the Cursor.
 */
struct ClassVisitor {
    import cpptooling.data.representation : CppClassName, CppClassVirtual,
        CppClass, VirtualType;

    /** Make a ClassVisitor by deriving the name and virtuality from a Clang Cursor.
     */
    static auto make(ref Cursor c) {
        auto name = CppClassName(c.spelling);
        auto r = ClassVisitor(name);
        return r;
    }

    @disable this();

    private this(CppClassName name) {
        this.data = CppClass(name);
    }

    auto visit(ref Cursor c) {
        ///TODO add information if it is a public/protected/private class.
        if (!c.isDefinition) {
            logger.error("Expected cursor to be a definition but it is:", to!string(c));
            return data;
        }

        return ClassDescendVisitor(data).visit(c);
    }

private:
    CppClass data;
}

AccessType toAccessType(CX_CXXAccessSpecifier accessSpec) {
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

struct NamespaceDescendVisitor {
    import std.typecons : NullableRef;
    import cpptooling.data.representation : CppNamespace;

    @disable this();

    this(NullableRef!CppNamespace data) {
        if (data.isNull) {
            logger.fatal("CppNamespace parameter is null");
            throw new Exception("CppNamespace parameter is null");
        }
        this.data = &data.get();
    }

    void visit(ref Cursor c) {
        visitAst!(typeof(this))(c, this);
    }

    void applyRoot(ref Cursor root) {
        logNode(root, 0);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        bool descend = true;

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            // visit node to find nested classes
            data.put(ClassVisitor.make(c).visit(c));
            break;
        case CXCursor_FunctionDecl:
            data.put(FunctionVisitor.make(c).visit(c));
            descend = false;
            break;
        case CXCursor_Namespace:
            descend = false;
            break;
        default:
            break;
        }

        return descend;
    }

private:
    CppNamespace* data;
}

/** Extracts all namespaces.
 * Visits the interior of its own namespace with a Descender.
 * For others use a standard NamespaceVisitor.
 * The design separates the logic for finding namespaces inside the first from
 * analyzing the content of a namespace.
 */
struct NamespaceVisitor {
    import std.typecons : NullableRef;
    import cpptooling.data.representation : CppNsStack, CppNs, CppNamespace;

    static auto make(ref Cursor c) {
        return NamespaceVisitor.make(c, CppNsStack.init);
    }

    /** Initialize the visitor with a stack constiting of [c] + [stack_].
     * Params:
     *  c = cursor to pull name from, must be a namespace.
     *  stack = namespace nesting that c reside in.
     */
    static auto make(ref Cursor c, const CppNsStack stack) {
        if (c.kind != CXCursorKind.CXCursor_Namespace) {
            logger.error("Expected cursor to be of type Namespace. It is: ", to!string(c));
        }
        auto stack_ = stack.dup;
        stack_ ~= CppNs(c.spelling);

        return NamespaceVisitor(stack_);
    }

    @disable this();

    private this(const CppNsStack stack) {
        this.data = typeof(data)(stack);
        this.stack = stack.dup;
    }

    auto visit(ref Cursor c) {
        visitAst!(typeof(this))(c, this);
        return data;
    }

    void applyRoot(ref Cursor root) {
        logNode(root, 0);
        auto d = NullableRef!CppNamespace(&data);
        NamespaceDescendVisitor(d).visit(root);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        logNode(c, 0);

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_Namespace:
            data.put(NamespaceVisitor.make(c, stack).visit(c));
            break;
        default:
            break;
        }

        return false;
    }

private:
    CppNamespace data;
    CppNsStack stack;
}

/// Root visitor of AST.
struct ParseContext {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.utility.stack : VisitNodeDepth;

    private VisitNodeDepth depth_;
    alias depth_ this;

    void visit(Cursor cursor) {
        visitAst!(typeof(this))(cursor, this);
    }

    void applyRoot(ref Cursor root) {
        logNode(root, depth);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        bool descend = true;
        logNode(c, depth);
        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            // visit node to find nested classes
            root.put(ClassVisitor.make(c).visit(c));
            break;
        case CXCursor_CXXBaseSpecifier:
            descend = false;
            break;
        case CXCursor_Namespace:
            root.put(NamespaceVisitor.make(c).visit(c));
            descend = false;
            break;
        case CXCursor_FunctionDecl:
            root.put(FunctionVisitor.make(c).visit(c));
            descend = false;
            break;

        default:
            break;
        }

        return descend;
    }

    CppRoot root;
}

private:

/** Travers a node tree and gather all paramdecl to an array.
 * Params:
 * T = Type that shall wrap TypeKindVariable.
 * cursor = A node containing ParmDecl nodes as children.
 * Example:
 * -----
 * class Simple{ Simple(char x, char y); }
 * -----
 * The AST for the above is kind of the following:
 * Example:
 * ---
 * Simple [CXCursor_Constructor Type(CXType(CXType_FunctionProto))
 *   x [CXCursor_ParmDecl Type(CXType(CXType_Char_S))
 *   y [CXCursor_ParmDecl Type(CXType(CXType_Char_S))
 * ---
 * It is translated to the array [("char", "x"), ("char", "y")].
 */
auto paramDeclTo(Cursor cursor) {
    import translator.Type : TypeKind, translateType;
    import cpptooling.data.representation : TypeKindVariable, CppVariable,
        makeCxParam, CxParam;
    import std.traits;

    CxParam[] params;

    foreach (param; cursor.func.parameters) {
        auto type = translateType(param.type);
        params ~= makeCxParam(TypeKindVariable(type, CppVariable(param.spelling)));
    }

    if (cursor.func.isVariadic) {
        params ~= makeCxParam();
    }

    debug {
        foreach (p; params) {
            logger.trace(p.toString);
        }
    }

    return params;
}
