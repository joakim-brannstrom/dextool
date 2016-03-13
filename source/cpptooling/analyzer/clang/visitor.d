// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.visitor;

import std.conv : to;
import logger = std.experimental.logger;

import deimos.clang.index;

import clang.Cursor;
import clang.SourceLocation;

import cpptooling.analyzer.clang.utility;
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

struct VariableVisitor {
    static auto make(ref Cursor) {
        return typeof(this)();
    }

    auto visit(ref Cursor c) {
        import cpptooling.data.representation : CxGlobalVariable, CppVariable,
            CxLocation;
        import cpptooling.analyzer.clang.type : TypeKind, translateType;

        auto name = CppVariable(c.spelling);
        auto type = translateType(c.type);
        auto loc = toInternal!CxLocation(c.location());

        auto var = CxGlobalVariable(type.unwrap, name, loc);
        logger.info("variable:", var.toString);

        return var;
    }
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
        import cpptooling.analyzer.clang.type : TypeKind, translateType;

        auto params = paramDeclTo(c);
        auto name = CFunctionName(c.spelling);
        auto return_type = CxReturnType(translateType(c.func.resultType).unwrap);
        auto is_variadic = c.func.isVariadic ? VariadicType.yes : VariadicType.no;
        auto loc = toInternal!CxLocation(c.location());

        auto func = CFunction(name, params, return_type, is_variadic, loc);
        logger.info("function: ", func.toString);

        return func;
    }
}

/** Extract information regarding a class inheritance.
 *
 */
struct InheritVisitor {
    import cpptooling.data.representation;
    import cpptooling.utility.stack : VisitNodeDepth;

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

    auto visit(ref Cursor c)
    in {
        assert(c.isReference);
    }
    body {
        static struct GatherNs {
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
        GatherNs gather;
        backtrackNode!(kind => kind == CXCursorKind.CXCursor_Namespace)(c_ref,
                gather, "cxx_base -> ns", 1);

        import std.algorithm : each;
        import std.range : retro;

        //TODO would copy work instead of each?
        retro(gather.stack).each!(a => data.put(a));

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

/** Descend a class cursor to extract interior information.
 * C'tors, d'tors, member methods etc.
 * Cleanly separates the functionality for initializing the container for a
 * class and the analyze logic.
 *
 * Note that it also traverses the inheritance chain.
 */
struct ClassDescendVisitor {
    import cpptooling.data.representation;
    import cpptooling.data.symbol.container;

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
            data.put(class_, cast(TypedefType!CppAccess) accessType);
            container.put(class_, class_.fullyQualifiedName);
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
        auto tor = CppDtor(name, accessType, CppVirtualMethod(c.func.isVirtual
                ? VirtualType.Yes : VirtualType.No));
        logger.info("dtor: ", tor.toString);
        data.put(tor);
    }

    void applyInherit(ref Cursor c, ref Cursor parent) {
        auto inherit = InheritVisitor.make(c).visit(c);
        data.put(inherit);
    }

    void applyField(ref Cursor c, const CppAccess accessType) {
        import std.typecons : TypedefType;
        import cpptooling.analyzer.clang.type : translateType;
        import cpptooling.data.representation : TypeKindVariable;

        auto tk = translateType(c.type).unwrap;
        auto name = CppVariable(c.spelling);

        data.put(TypeKindVariable(tk, name), cast(TypedefType!CppAccess) accessType);
    }

    void applyMethod(ref Cursor c, ref Cursor parent) {
        import cpptooling.analyzer.clang.type : TypeKind, translateType;
        import cpptooling.data.representation : CppMethodOp;

        static bool helperIsOperator(CppMethodName name_) {
            import std.algorithm : among;

            if (name_.length <= 8) {
                // "operator" keyword is 8 char long, thus an optimization to first look
                // at the length
                return false;
            } else if (name_[8 .. $].among("=", "==", "+=", "-=", "++", "--", "+", "-", "*")) {
                return true;
            }

            return false;
        }

        auto params = paramDeclTo(c);
        auto name = CppMethodName(c.spelling);
        auto return_type = CxReturnType(translateType(c.func.resultType).unwrap);

        auto is_virtual = CppVirtualMethod(VirtualType.No);
        if (c.func.isPureVirtual) {
            is_virtual = CppVirtualMethod(VirtualType.Pure);
        } else if (c.func.isVirtual) {
            is_virtual = CppVirtualMethod(VirtualType.Yes);
        }

        if (helperIsOperator(name)) {
            auto op = CppMethodOp(name, params, return_type, accessType,
                    CppConstMethod(c.func.isConst), is_virtual);
            logger.info("operator: ", op.toString);
            data.put(op);
        } else {
            auto method = CppMethod(name, params, return_type, accessType,
                    CppConstMethod(c.func.isConst), is_virtual);
            logger.info("method: ", method.toString);
            data.put(method);
        }
    }

private:
    CppClass data;
    CppAccess accessType;
    Container* container;
}

/** Extract information about a class.
 */
struct ClassVisitor {
    import cpptooling.data.representation : CppClassName, CppClassVirtual,
        CppClass, CxLocation, VirtualType, CppNsStack, CppInherit;
    import cpptooling.data.symbol.container;

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
        auto loc = toInternal!CxLocation(c.location());
        auto name = CppClassName(c.spelling);
        auto r = ClassVisitor(name, loc, reside_in_ns);
        return r;
    }

    /// The constructor is disabled to force the class to be in a consistent state.
    @disable this();

    //TODO consider making it public. The reason for private is dubious.
    private this(CppClassName name, CxLocation loc, CppNsStack reside_in_ns) {
        this.data = CppClass(name, loc, CppInherit[].init, reside_in_ns);
    }

    auto visit(ref Cursor c, ref Container container)
    in {
        assert(c.kind == CXCursorKind.CXCursor_ClassDecl);
    }
    body {
        ///TODO add information if it is a public/protected/private class.
        ///TODO add metadata to the class if it is a definition or declaration
        if (!c.isDefinition) {
            logger.error("Expected cursor to be a definition but it is: ",
                    to!string(c), " File:", c.location.toString);
            return data;
        }

        return ClassDescendVisitor(data).visit(c, container);
    }

private:
    CppClass data;
}

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

struct NamespaceDescendVisitor {
    import std.typecons : NullableRef;
    import cpptooling.data.representation : CppNamespace;
    import cpptooling.data.symbol.container;

    @disable this();

    //TODO why using NullableRef? Avoid runtime errors....
    this(NullableRef!CppNamespace data) {
        if (data.isNull) {
            logger.fatal("CppNamespace parameter is null");
            throw new Exception("CppNamespace parameter is null");
        }
        this.data = &data.get();
    }

    void visit(ref Cursor c, ref Container container)
    in {
        assert(c.kind == CXCursorKind.CXCursor_Namespace);
        assert(&container !is null);
    }
    body {
        this.container = &container;
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
            auto class_ = ClassVisitor.make(c, data.resideInNs.dup).visit(c, *container);
            container.put(class_, class_.fullyQualifiedName);
            data.put(class_);
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
    Container* container;
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
    import cpptooling.data.symbol.container;

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

    auto visit(ref Cursor c, ref Container container)
    in {
        assert(c.kind == CXCursorKind.CXCursor_Namespace);
        assert(&container !is null);
    }
    body {
        this.container = &container;
        visitAst!(typeof(this))(c, this);
        return data;
    }

    void applyRoot(ref Cursor root) {
        logNode(root, 0);
        auto d = NullableRef!CppNamespace(&data);
        NamespaceDescendVisitor(d).visit(root, *container);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        switch (c.kind) with (CXCursorKind) {
        case CXCursor_Namespace:
            logNode(c, 0);
            data.put(NamespaceVisitor.make(c, stack).visit(c, *container));
            break;
        default:
            break;
        }

        return false;
    }

private:
    CppNamespace data;
    CppNsStack stack;
    Container* container;
}

/// Root visitor of AST.
struct ParseContext {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container;
    import cpptooling.utility.stack : VisitNodeDepth;

    private VisitNodeDepth depth_;
    alias depth_ this;

    void visit(Cursor cursor) {
        visitAst!(typeof(this))(cursor, this);

        debug {
            logger.trace(container.toString);
        }
    }

    void applyRoot(ref Cursor c) {
        import cpptooling.data.representation : CxLocation;

        logNode(c, depth);

        // retrieving the location from a root is via spelling.
        auto loc = CxLocation();
        loc.file = c.spelling;
        root = CppRoot(loc);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        bool descend = true;
        logNode(c, depth);
        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            import cpptooling.data.representation : CppNsStack;

            // visit node to find nested classes
            auto class_ = ClassVisitor.make(c, CppNsStack.init).visit(c, container);
            container.put(class_, class_.fullyQualifiedName);
            root.put(class_);
            break;
        case CXCursor_CXXBaseSpecifier:
            descend = false;
            break;
        case CXCursor_Namespace:
            root.put(NamespaceVisitor.make(c).visit(c, container));
            descend = false;
            break;
        case CXCursor_FunctionDecl:
            root.put(FunctionVisitor.make(c).visit(c));
            descend = false;
            break;
        case CXCursor_VarDecl:
            ///TODO ugly hack. Move this information to the representation.
            /// but for now skipping all definitions
            if (c.storageClass() == CX_StorageClass.CX_SC_Extern) {
                root.put(VariableVisitor.make(c).visit(c));
            }
            descend = false;
            break;
        default:
            break;
        }

        return descend;
    }

    CppRoot root;
    Container container;
}
