// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.visitor;

import std.conv : to;
import std.typecons : Nullable, NullableRef;
import logger = std.experimental.logger;

import deimos.clang.index;

import clang.Cursor;
import clang.SourceLocation;

import cpptooling.analyzer.type;
import cpptooling.analyzer.clang.type : TypeKind, retrieveType;
import cpptooling.analyzer.clang.utility;
import cpptooling.data.type;
import cpptooling.data.symbol.container : Container;
import cpptooling.data.symbol.types : USRType;
import cpptooling.utility.clang : visitAst, logNode;

// Store the derived type information
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

private void put(ref Nullable!TypeResult tr, ref Container container) {
    if (!tr.isNull) {
        logTypeResult(tr);
        container.put(tr.primary.kind);
        foreach (e; tr.extra) {
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

struct VariableVisitor {
    import cpptooling.data.representation : CxGlobalVariable;

    static auto make(ref Cursor) {
        return typeof(this)();
    }

    CxGlobalVariable visit(ref Cursor c, ref Container container)
    out (result) {
        logger.info("variable:", result.toString);
    }
    body {
        import cpptooling.data.representation : CppVariable;

        auto type = retrieveType(c, container);
        put(type, container);

        auto name = CppVariable(c.spelling);
        auto loc = toInternal(c.location());

        return CxGlobalVariable(type.primary, name, loc);
    }
}

/// Seems more complicated than it need to be but the goal is to keep the
/// API the same.
/// TODO use isOperator to detect if the function is an operator. Thus if it is
/// mark it as such. Probably need to modify cpptooling.data.representation.
struct FunctionVisitor {
    import cpptooling.data.representation : CxParam, CFunctionName,
        CxReturnType, CFunction, VariadicType, LocationTag, StorageClass;

    static auto make(ref Cursor) {
        return typeof(this)();
    }

    Nullable!CFunction visit(ref Cursor c, ref Container container) {
        import std.algorithm : among;
        import std.functional : pipe;

        // hint, start reading the function from the bottom up.
        // design is pipe and data transformation

        Nullable!TypeResult extractAndStoreRawType(ref Cursor c) {
            auto tr = retrieveType(c, container);
            if (tr.isNull) {
                return tr;
            }

            assert(tr.primary.kind.info.kind.among(TypeKind.Info.Kind.func,
                    TypeKind.Info.Kind.typeRef, TypeKind.Info.Kind.simple));
            put(tr, container);

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

            logTypeResult(tr);
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
            auto data = ComposeData(tr);

            data.name = CFunctionName(c.spelling);
            data.loc = toInternal(c.location());

            switch (c.storageClass()) with (CX_StorageClass) {
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
                    data.tr.primary.kind.info.returnAttr)), is_variadic,
                    data.storageClass, data.loc);
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
            (c);
        // dfmt on
        logger.info(!rval.isNull, "function: ", rval.get.toString);

        return rval;
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
        data.usr = cast(USRType) rt.primary.kind.usr;

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

/** Extract information about a class.
 */
struct ClassVisitor {
    import cpptooling.data.representation : CppClassName, CppClassVirtual,
        CppClass, LocationTag, ClassVirtualType, CppNsStack, CppInherit;
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
        put(c, *container);

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            // visit node to find nested classes
            auto class_ = ClassVisitor.make(c, data.resideInNs.dup).visit(c, *container);
            if (!class_.isNull) {
                container.put(class_, class_.fullyQualifiedName);
                data.put(class_);
            }
            break;
        case CXCursor_FunctionDecl:
            auto f = FunctionVisitor.make(c).visit(c, *container);
            if (!f.isNull) {
                data.put(f.get);
            }
            descend = false;
            break;
        case CXCursor_Namespace:
            descend = false;
            break;
        case CXCursor_VarDecl:
            ///TODO ugly hack. Move this information to the representation.
            /// but for now skipping all definitions
            if (c.storageClass() == CX_StorageClass.CX_SC_Extern) {
                data.put(VariableVisitor.make(c).visit(c, *container));
            }
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
        logger.info("namespace: ", cast(string) c.spelling);
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
        put(c, *container);

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

    @disable this();

    this(ref CppRoot root, ref Container cont) {
        this.root.bind(&root);
        this.container.bind(&cont);
    }

    void visit(Cursor cursor) {
        visitAst!(typeof(this))(cursor, this);

        debug {
            logger.trace(container.get.toString);
        }
    }

    void applyRoot(ref Cursor c) {
        import cpptooling.data.type : LocationTag;

        logNode(c, depth);

        auto loc = LocationTag(Location(c.translationUnit.file.name));
        root.setLocation(loc);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        bool descend = true;

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            import cpptooling.data.representation : CppNsStack;

            // visit node to find nested classes
            auto class_ = ClassVisitor.make(c, CppNsStack.init).visit(c, container);
            if (!class_.isNull) {
                container.put(class_, class_.fullyQualifiedName);
                root.put(class_);
            }
            break;
        case CXCursor_CXXBaseSpecifier:
            descend = false;
            break;
        case CXCursor_Namespace:
            //TODO change NS visitor to take a ref.
            // The same NS can occur many times in the AST
            root.put(NamespaceVisitor.make(c).visit(c, container));
            descend = false;
            break;
        case CXCursor_FunctionDecl:
            auto f = FunctionVisitor.make(c).visit(c, container);
            if (!f.isNull) {
                root.put(f.get);
            }
            descend = false;
            break;
        case CXCursor_VarDecl:
            ///TODO ugly hack. Move this information to the representation.
            /// but for now skipping all definitions
            if (c.storageClass() == CX_StorageClass.CX_SC_Extern) {
                root.put(VariableVisitor.make(c).visit(c, container));
            }
            descend = false;
            break;
        default:
            break;
        }

        return descend;
    }

    NullableRef!CppRoot root;
    NullableRef!Container container;
}
