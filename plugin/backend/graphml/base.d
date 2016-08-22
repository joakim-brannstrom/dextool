/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.backend.graphml.base;

import std.format : FormatSpec;
import std.range : isOutputRange;
import std.traits : isSomeString, Unqual;
import std.typecons : scoped, Nullable, Flag, Yes;
import logger = std.experimental.logger;

import cpptooling.analyzer.clang.analyze_helper : VarDeclResult,
    FieldDeclResult;
import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.analyzer.kind : resolveCanonicalType, resolvePointeeType;
import cpptooling.analyzer.type : TypeKindAttr, TypeKind, TypeAttr,
    toStringDecl;
import cpptooling.data.symbol.container : Container;
import cpptooling.data.type : CppAccess, LocationTag, Location, USRType,
    AccessType;

import plugin.backend.graphml.xml;

version (unittest) {
    import unit_threaded;
    import std.array : appender;

    private struct DummyRecv {
        import std.array : Appender;

        Appender!(string)* buf;

        void put(const(char)[] s) {
            buf.put(s);
        }
    }
}

static import cpptooling.data.class_classification;

@safe interface Controller {
}

@safe interface Parameters {
}

/// Data produced by the backend to be handled by the frontend.
@safe interface Products {
    import application.types : FileName;

    /** Put content, by appending, to specified file.
     *
     * Params:
     *   fname = filename
     *   content = slice to write
     */
    void put(FileName fname, const(char)[] content);
}

final class GraphMLAnalyzer(ReceiveT) : Visitor {
    import cpptooling.analyzer.clang.ast : TranslationUnit, ClassDecl, VarDecl,
        FunctionDecl, Namespace, UnexposedDecl, StructDecl, CompoundStmt,
        Constructor, Destructor, CXXMethod, Declaration, ClassTemplate,
        ClassTemplatePartialSpecialization, FunctionTemplate, UnionDecl;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl, analyzeRecord, analyzeTranslationUnit;
    import cpptooling.data.representation : CppRoot, CppNs, CFunction,
        CxReturnType;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.data.type : LocationTag, Location;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    private {
        ReceiveT recv;
        Controller ctrl;
        Parameters params;
        Products prod;
        Container* container;

        CppNs[] scope_stack;
    }

    this(ReceiveT recv, Controller ctrl, Parameters params, Products prod, ref Container container) {
        this.recv = recv;
        this.ctrl = ctrl;
        this.params = params;
        this.prod = prod;
        this.container = &container;
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char formatSpec) const {
        container.toString(w, formatSpec);
    }

    override string toString() @safe const {
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

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeTranslationUnit(v, *container, indent);
        recv.put(result);

        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.type : retrieveType;
        import cpptooling.analyzer.clang.utility : put;

        auto type = () @trusted{
            return retrieveType(v.cursor, *container, indent);
        }();
        put(type, *container, indent);

        if (!type.isNull) {
            recv.put(type.get.primary.type);
        }

        v.accept(this);
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());

        // An unexposed may be:

        // extern "C" void func_c_linkage();
        // UnexposedDecl "" extern "C" {...
        //   FunctionDecl "fun_c_linkage" void func_c_linkage
        v.accept(this);
    }

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeVarDecl(v, *container, indent);

        if (scope_stack.length == 0) {
            recv.put(result);
        } else {
            recv.put(result, scope_stack);
        }
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, *container, indent);
        recv.put(result);
        assert(result.isValid);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(result.type, ctrl,
                    recv, *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());

        () @trusted{ scope_stack ~= CppNs(v.cursor.spelling); }();
        // pop the stack when done
        scope (exit)
            scope_stack = scope_stack[0 .. $ - 1];

        // fill the namespace with content from the analyse
        v.accept(this);
    }

    // === Class and Struct ===
    override void visit(const(FunctionTemplate) v) {
    }

    /** Implicit promise that THIS method will output the class node after the
     * class has been classified.
     */
    override void visit(const(ClassDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);
        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(ClassTemplate) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);
        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(ClassTemplatePartialSpecialization) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);
        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(StructDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);
        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(UnionDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);
        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    private auto visitRecord(T, ResultT)(const(T) v, ref ResultT result) @trusted {
        import std.meta : staticIndexOf;
        import cpptooling.data.type : AccessType;

        static if (staticIndexOf!(Unqual!T, ClassDecl, ClassTemplate,
                ClassTemplatePartialSpecialization) != -1) {
            auto access_init = AccessType.Private;
        } else {
            auto access_init = AccessType.Public;
        }

        auto visitor = scoped!(ClassVisitor!(ReceiveT))(result.type, scope_stack,
                access_init, result.name, ctrl, recv, *container, indent + 1);
        v.accept(visitor);

        return visitor.node;
    }

    // BEGIN. Needed for when the methods are defined outside of the class declaration.
    // These functions may ONLY ever create relations. Never new nodes.
    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());
        visitClassStructMethod(v);
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());
        visitClassStructMethod(v);
    }

    override void visit(const(CXXMethod) v) {
        mixin(mixinNodeLog!());
        visitClassStructMethod(v);
    }

    private auto visitClassStructMethod(T)(const(T) v) {
        import std.algorithm : among;
        import deimos.clang.index : CXCursorKind;

        auto parent = v.cursor.semanticParent;

        // can't handle ClassTemplates etc yet
        if (!parent.kind.among(CXCursorKind.CXCursor_ClassDecl, CXCursorKind.CXCursor_StructDecl)) {
            return;
        }

        auto result = analyzeRecord(parent, *container, indent);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(result.type, ctrl,
                    recv, *container, indent + 1);
            v.accept(visitor);
        }();
    }
    // END.
}

/**
 *
 * The $(D ClassVisitor) do not know when the analyze is finished.
 * Therefore from the viewpoint of $(D ClassVisitor) classification is an
 * ongoing process. It is the responsibility of the caller of $(D
 * ClassVisitor) to use the final result of the classification together with
 * the style.
 */
private final class ClassVisitor(ReceiveT) : Visitor {
    import std.algorithm : map, copy, each, joiner;
    import std.array : Appender;
    import std.conv : to;
    import std.typecons : scoped, TypedefType, NullableRef;

    import cpptooling.analyzer.clang.ast : ClassDecl, ClassTemplate, ClassTemplatePartialSpecialization, StructDecl,
        CXXBaseSpecifier, Constructor, Destructor, CXXMethod, FieldDecl,
        CXXAccessSpecifier, TypedefDecl, UnionDecl;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeRecord,
        analyzeConstructor, analyzeDestructor,
        analyzeCXXMethod, analyzeFieldDecl, analyzeCXXBaseSpecified,
        toAccessType;
    import cpptooling.data.type : MemberVirtualType;
    import cpptooling.data.representation : CppNsStack, CppNs, AccessType,
        CppAccess, CppDtor, CppCtor, CppMethod, CppClassName;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    import cpptooling.data.class_classification : ClassificationState = State;
    import cpptooling.data.class_classification : classifyClass, MethodKind;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    /** Type representation of this class.
     * Used as the source of the outgoing relations from this class.
     */
    TypeKindAttr this_;

    NodeRecord node;

    private {
        Controller ctrl;
        NullableRef!ReceiveT recv;

        Container* container;
        CppNsStack scope_stack;
        CppAccess access;

        /// If the class has any members.
        Flag!"hasMember" hasMember;

        /** Classification of the class.
         * Affected by methods.
         */
        ClassificationState classification;
    }

    this(ref const(TypeKindAttr) this_, const(CppNs)[] reside_in_ns, AccessType init_access,
            CppClassName name, Controller ctrl, ref ReceiveT recv,
            ref Container container, in uint indent) {
        this.ctrl = ctrl;
        this.recv = &recv;
        this.container = &container;
        this.indent = indent;
        this.scope_stack = CppNsStack(reside_in_ns.dup);

        this.access = CppAccess(init_access);
        this.classification = ClassificationState.Unknown;

        this.this_ = this_;

        node.usr = this_.kind.usr;
        node.identifier = name;
    }

    /**
     * Has hidden data dependencies on:
     *  - hasMember.
     *  - current state of classification.
     *
     * Will update:
     *  - the internal state classification
     *  - the style stereotype
     */
    private void updateClassification(MethodKind kind, MemberVirtualType virtual_kind) {
        this.classification = classifyClass(this.classification, kind,
                virtual_kind, this.hasMember);
        this.node.stereotype = this.classification.toInternal!StereoType;
    }

    /// Nested class definitions.
    override void visit(const(ClassDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);

        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(ClassTemplate) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);

        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(ClassTemplatePartialSpecialization) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);

        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(StructDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);

        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    override void visit(const(UnionDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeRecord(v, *container, indent + 1);

        auto node = visitRecord(v, result);
        recv.put(result, scope_stack, node);
    }

    private auto visitRecord(T, ResultT)(const(T) v, ref ResultT result) @trusted {
        import std.meta : staticIndexOf;
        import cpptooling.data.type : AccessType;

        scope_stack ~= CppNs(cast(string) result.name);
        scope (exit)
            scope_stack = scope_stack[0 .. $ - 1];

        static if (staticIndexOf!(Unqual!T, ClassDecl, ClassTemplate,
                ClassTemplatePartialSpecialization) != -1) {
            auto access_init = AccessType.Private;
        } else {
            auto access_init = AccessType.Public;
        }

        auto visitor = scoped!(ClassVisitor!(ReceiveT))(result.type, scope_stack,
                access_init, result.name, ctrl, recv, *container, indent + 1);
        v.accept(visitor);

        return visitor.node;
    }

    /// Analyze the inheritance(s).
    override void visit(const(CXXBaseSpecifier) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeCXXBaseSpecified(v, *container, indent);

        recv.put(this_, result);
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeConstructor(v, *container, indent);
        updateClassification(MethodKind.Ctor, MemberVirtualType.Unknown);

        auto tor = CppCtor(result.type.kind.usr, result.name, result.params, access);
        auto func = NodeFunction(result.type.kind.usr, tor.toString, result.name, result.location);
        node.methods.put(func);

        recv.put(this_, result, access);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(result.type, ctrl,
                    recv, *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeDestructor(v, *container, indent);
        updateClassification(MethodKind.Dtor, cast(MemberVirtualType) result.virtualKind);

        auto tor = CppDtor(result.type.kind.usr, result.name, access, result.virtualKind);
        auto func = NodeFunction(result.type.kind.usr, tor.toString, result.name, result.location);
        node.methods.put(func);

        recv.put(this_, result, access);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(result.type, ctrl,
                    recv, *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(CXXMethod) v) {
        mixin(mixinNodeLog!());
        import cpptooling.data.type : CppConstMethod;
        import cpptooling.data.representation : CppMethod;

        auto result = analyzeCXXMethod(v, *container, indent);
        updateClassification(MethodKind.Method, cast(MemberVirtualType) result.virtualKind);

        auto method = CppMethod(result.type.kind.usr, result.name, result.params,
                result.returnType, access, CppConstMethod(result.isConst), result.virtualKind);
        auto func = NodeFunction(result.type.kind.usr, method.toString,
                result.name, result.location);
        node.methods.put(func);

        recv.put(this_, result, access);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(result.type, ctrl,
                    recv, *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(FieldDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFieldDecl(v, *container, indent);

        auto field = NodeField(result.instanceUSR, result.name, result.type,
                access, decideColor(result), result.location);
        node.attributes.put(field);

        // TODO probably not necessary for classification to store it as a
        // member. Instead extend MethodKind to having a "Member".
        hasMember = Yes.hasMember;
        updateClassification(MethodKind.Unknown, MemberVirtualType.Unknown);

        recv.put(this_, result, access);
    }

    override void visit(const(TypedefDecl) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.type : retrieveType;
        import cpptooling.analyzer.clang.utility : put;

        auto result = () @trusted{
            return retrieveType(v.cursor, *container, indent + 1);
        }();
        put(result, *container, indent + 1);

        if (!result.isNull) {
            auto tnode = NodeType(result.primary.type);
            node.types.put(tnode);
        }
    }

    override void visit(const(CXXAccessSpecifier) v) @trusted {
        mixin(mixinNodeLog!());
        access = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }
}

/** Visit a function or method body.
 *
 */
private final class BodyVisitor(ReceiveT) : Visitor {
    import std.algorithm;
    import std.array;
    import std.conv;
    import std.typecons;

    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper;
    import cpptooling.data.representation;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    /** Type representation of parent.
     * Used as the source of the outgoing relations from this class.
     */
    TypeKindAttr parent;

    private {
        Controller ctrl;
        NullableRef!ReceiveT recv;

        Container* container;
    }

    this(const(TypeKindAttr) parent, Controller ctrl, ref ReceiveT recv,
            ref Container container, const uint indent) {
        this.parent = parent;
        this.ctrl = ctrl;
        this.recv = &recv;
        this.container = &container;
        this.indent = indent;
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.utility : isGlobalOrNamespaceScope;

        // accessing a global
        if (v.cursor.isGlobalOrNamespaceScope) {
            auto result = analyzeVarDecl(v, *container, indent);
            recv.put(parent, result.type);
        }

        v.accept(this);
    }

    override void visit(const(CallExpr) v) @trusted {
        mixin(mixinNodeLog!());
        // assuming the needed reference information of the node is found by traversing the AST

        auto visitor = scoped!(RefVisitor)(ctrl, *container, indent + 1);
        v.accept(visitor);

        processRef(visitor);
    }

    override void visit(const(DeclRefExpr) v) @trusted {
        mixin(mixinNodeLog!());
        visitRef(v);
    }

    override void visit(const(MemberRefExpr) v) @trusted {
        mixin(mixinNodeLog!());
        visitRef(v);
    }

private:
    void visitRef(T)(const(T) v) @trusted {
        // assuming there are no sub nodes so therefor not calling v.accept(visitor)

        auto visitor = scoped!(RefVisitor)(ctrl, *container, indent + 1);
        visitor.visitReferenced(v.cursor);
        processRef(visitor);
    }

    void processRef(T)(ref const(T) r) {
        foreach (usr; r.destinations.data) {
            recv.put(parent.kind.usr, usr);
        }

        foreach (type; r.extraTypes.data) {
            recv.putBodyNode(type);
        }
    }
}

/** Analyze a reference node.
 * The data gathered is:
 *     - types
 *     - accessing global variables
 *     - function calls
 * The gathered targets are stored in $(D destinations).
 */
private final class RefVisitor : Visitor {
    import std.algorithm;
    import std.array;
    import std.conv;
    import std.typecons;

    import clang.Cursor : Cursor;
    import deimos.clang.index : CXCursorKind;

    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper;
    import cpptooling.data.representation;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    // It is assumed that the nodes the edges connect are analysed and
    // retrieved from elsewhere.
    Appender!(USRType[]) destinations;

    // The assumtion fall apart for functions.
    // For example __builtins will trigger cases where an edge is created but no node.
    // To handle this extra dummy "type node" are created for functions
    Appender!(TypeKindAttr[]) extraTypes;

    private {
        Controller ctrl;
        Container* container;
        bool[USRType] visited;
    }

    this(Controller ctrl, ref Container container, const uint indent) {
        this.ctrl = ctrl;
        this.container = &container;
        this.indent = indent;
    }

    void visitReferenced(const(Cursor) cursor) @trusted {
        import cpptooling.analyzer.clang.type : makeEnsuredUSR;

        auto ref_ = cursor.referenced;

        // avoid cycles
        auto usr = makeEnsuredUSR(ref_, indent + 1);
        if (usr in visited) {
            return;
        }
        visited[usr] = true;

        logNode(ref_, indent);

        import cpptooling.analyzer.clang.ast.tree : dispatch;

        dispatch(ref_, this);
    }

    // Begin: Referencing
    override void visit(const(MemberRefExpr) v) {
        mixin(mixinNodeLog!());
        visitReferenced(v.cursor);
        v.accept(this);
    }

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());
        visitReferenced(v.cursor);
        v.accept(this);
    }
    // End: Referencing

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeFunctionDecl(v, *container, indent);
        if (result.isValid) {
            destinations.put(result.type.kind.usr);
            extraTypes.put(result.type);
        }
    }

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.utility : isGlobalOrNamespaceScope;

        // the root node for the visitor is a reference.
        // it may therefor be an access to a global variable.

        // accessing a global
        if (v.cursor.isGlobalOrNamespaceScope) {
            auto result = analyzeVarDecl(v, *container, indent);
            destinations.put(result.instanceUSR);
        }
    }

    // Begin: Class struct
    override void visit(const(FieldDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeFieldDecl(v, *container, indent);
        destinations.put(result.instanceUSR);
        // a template may result in extra nodes. e.g std::string's .c_str()
        extraTypes.put(result.type);
    }

    override void visit(const(CXXMethod) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeCXXMethod(v, *container, indent);
        destinations.put(result.type.kind.usr);
        // a template may result in extra nodes. e.g std::string's .c_str()
        extraTypes.put(result.type);
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeConstructor(v, *container, indent);
        destinations.put(result.type.kind.usr);
        // a template may result in extra nodes. e.g std::string's .c_str()
        extraTypes.put(result.type);
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeDestructor(v, *container, indent);
        destinations.put(result.type.kind.usr);
        // a template may result in extra nodes. e.g std::string's .c_str()
        extraTypes.put(result.type);
    }
    // End: Class struct

    // Begin: Generic
    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }
    // End: Generic
}

private T toInternal(T, S)(S value) @safe pure nothrow @nogc 
        if (isSomeString!T && (is(S == CppAccess) || is(S == AccessType))) {
    import cpptooling.data.representation : AccessType;

    final switch (value) {
    case AccessType.Private:
        return "-";
    case AccessType.Protected:
        return "#";
    case AccessType.Public:
        return "+";
    }
}

private T toInternal(T, S)(S value) @safe pure nothrow @nogc 
        if (is(T == StereoType) && is(S == cpptooling.data.class_classification.State)) {
    final switch (value) with (cpptooling.data.class_classification.State) {
    case Unknown:
    case Normal:
    case Virtual:
        return StereoType.None;
    case Abstract:
        return StereoType.Abstract;
    case VirtualDtor: // only one method, a d'tor and it is virtual
    case Pure:
        return StereoType.Interface;
    }
}

/** Deduct if the type is primitive from the point of view of TransformToXmlStream.
 *
 * Filtering out arrays or ptrs of primitive types as to not result in too much
 * noise.
 */
private bool isPrimitive(T, LookupT)(const T data, LookupT lookup) @safe nothrow {
    static if (is(T == TypeKind)) {
        switch (data.info.kind) with (TypeKind.Info) {
        case Kind.primitive:
            return true;
        case Kind.array:
            foreach (ele; lookup.kind(data.info.element)) {
                return ele.info.kind == Kind.primitive;
            }
            return false;
        case Kind.pointer:
            foreach (ele; lookup.kind(data.info.pointee)) {
                return ele.info.kind == Kind.primitive;
            }
            return false;
        default:
            return false;
        }
    } else static if (is(T == NodeData)) {
        switch (data.tag.kind) with (NodeData.Tag) {
        case Kind.type:
            auto node = cast(NodeType) data.tag;
            return node.type.kind.isPrimitive(lookup);
        default:
            return false;
        }
    } else {
        static assert(0, "unsupported type: " ~ T.stringof);
    }
}

package struct NodeData {
    import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;

    alias Tag = TaggedAlgebraic!TagUnion;

    Tag tag;
    alias tag this;

    static union TagUnion {
        typeof(null) null_;
        NodeFunction func;
        NodeType type;
        NodeVariable variable;
        NodeRecord record;
        NodeFile file;
        NodeNamespace namespace;
        NodeField field;
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
        static import std.format;
        import std.traits : FieldNameTuple;

        enum case_ = "case Tag.Kind.%s: auto n = cast(%s) tag; nodeToXml(n, w); break;\n";

        final switch (tag.kind) {
            foreach (tag_field; FieldNameTuple!TagUnion) {
                static if (tag_field == "null_") {
                    mixin("case Kind.null_: break;\n");
                } else {
                    alias tag_field_t = typeof(__traits(getMember, TagUnion, tag_field));
                    mixin(std.format.format(case_, tag_field, tag_field_t.stringof));
                }
            }
        }
    }
}

private ColorKind decideColor(ref const(VarDeclResult) result) @safe pure nothrow @nogc {
    import cpptooling.data.type : StorageClass;

    auto color = ColorKind.global;
    if (result.type.attr.isConst) {
        color = ColorKind.globalConst;
    } else if (result.storageClass == StorageClass.Static) {
        color = ColorKind.globalStatic;
    }

    return color;
}

private ColorKind decideColor(ref const(FieldDeclResult) result) @safe pure nothrow @nogc {
    // TODO extend to differentiate between const and mutable fields.
    return ColorKind.field;
}

/** Transform analyze data to a xml stream.
 *
 * XML nodes must never be duplicated.
 * An edge source or target must be to nodes that exist.
 *
 * # Strategy `class`
 * The generation of a `node` is delayed as long as possible for a class
 * declaration in the hope of finding the definition.
 * The delay is implemented with a cache.
 * When finalize is called the cache is forcefully transformed to `nodes`.
 * Even those symbols that only have a declaration as location.
 */
class TransformToXmlStream(RecvXmlT, LookupT) if (isOutputRange!(RecvXmlT, char)) {
    import std.range : only;
    import std.typecons : NullableRef;

    import cpptooling.analyzer.clang.analyze_helper : CXXBaseSpecifierResult,
        RecordResult, FieldDeclResult, CXXMethodResult,
        ConstructorResult, DestructorResult, VarDeclResult, FunctionDeclResult,
        TranslationUnitResult;
    import cpptooling.analyzer.type : TypeKindAttr, TypeKind, TypeAttr,
        toStringDecl;
    import cpptooling.data.type : USRType, LocationTag, Location, CppNs;
    import plugin.utility : MarkArray;

    private {
        MarkArray!NodeData node_cache;

        /// nodes may never be duplicated. If they are it is a violation of the
        /// data format.
        bool[USRType] streamed_nodes;
        /// Ensure that there are only ever one relation between two entities.
        /// It avoids the scenario (which is common) of thick patches of
        /// relations to common nodes.
        bool[USRType] streamed_edges;

        NullableRef!RecvXmlT recv;
        LookupT lookup;
    }

    this(ref RecvXmlT recv, LookupT lookup) {
        this.recv = &recv;
        this.lookup = lookup;
    }

@safe:

    ///
    void finalize() {
        if (node_cache.data.length == 0) {
            return;
        }

        debug {
            import std.range : enumerate;

            logger.tracef("%d nodes left in cache", node_cache.data.length);
            foreach (idx, ref n; node_cache.data.enumerate) {
                logger.tracef("  %d: %s", idx + 1, n.usr);
            }
        }

        void anyLocation(ref const(NodeData) type, ref const(LocationTag) loc) {
            if (type.isPrimitive(lookup)) {
                return;
            }

            import std.conv : to;

            debug logger.tracef("creating node %s (%s)", cast(string) type.usr,
                    type.tag.kind.to!string());

            NodeData node = type;
            node.location = loc;
            nodeIfMissing(streamed_nodes, recv, type.usr, node);
        }

        LocationCallback cb;
        cb.unknown = &anyLocation;
        cb.declaration = &anyLocation;
        cb.definition = &anyLocation;

        resolveLocation(cb, node_cache.data, lookup);
        node_cache.clear;
    }

    ///
    void put(ref const(TranslationUnitResult) result) {
        xmlComment(recv, result.fileName);

        // empty the cache if anything is left in it
        if (node_cache.data.length == 0) {
            return;
        }

        debug logger.tracef("%d nodes left in cache", node_cache.data.length);

        // ugly hack.
        // used by putDefinition
        // incremented in the foreach
        size_t idx = 0;

        void putDeclaration(ref const(NodeData) type, ref const(LocationTag) loc) {
            // hoping for the best that a definition is found later on.
            if (type.isPrimitive(lookup)) {
                node_cache.markForRemoval(idx);
            }
        }

        void putDefinition(ref const(NodeData) type, ref const(LocationTag) loc) {
            import std.algorithm : among;

            if (type.tag.kind.among(NodeData.Tag.Kind.record, NodeData.Tag.Kind.record)) {
                // do nothing. delaying until finalize.
                // a struct/class (record) bypasses the cache.
            } else if (!type.isPrimitive(lookup)) {
                NodeData node = type;
                node.location = loc;
                nodeIfMissing(streamed_nodes, recv, type.usr, node);
            }

            node_cache.markForRemoval(idx);
        }

        LocationCallback cb;
        cb.unknown = &putDeclaration;
        cb.declaration = &putDeclaration;
        cb.definition = &putDefinition;

        foreach (ref item; node_cache.data) {
            resolveLocation(cb, only(item), lookup);
            ++idx;
        }

        debug logger.tracef("%d nodes left in cache", node_cache.data.length);

        node_cache.doRemoval;
    }

    /** Create a raw relation between two identifiers.
     */
    void put(const(USRType) src, const(USRType) dst) {
        addEdge(streamed_edges, recv, src, dst);
    }

    /** Create a raw relation between two types.
     */
    void put(const(TypeKindAttr) src, const(TypeKindAttr) dst) {
        edgeIfNotPrimitive(streamed_edges, recv, src, dst, lookup);
    }

    /** Create a raw node for a type.
     */
    void put(const(TypeKindAttr) type) {
        if (!type.kind.isPrimitive(lookup)) {
            auto node = NodeType(type, LocationTag(null));
            nodeIfMissing(streamed_nodes, recv, type.kind.usr, NodeData(NodeData.Tag(node)));
        }
    }

    /** Create a _possible_ node from a body inspection.
     * It delays the creation of the node until the translation unit is fully
     * analyzed.
     */
    void putBodyNode(const(TypeKindAttr) type) {
        if (!type.kind.isPrimitive(lookup)) {
            auto node = NodeType(type, LocationTag(null));
            putToCache(NodeData(NodeData.Tag(node)));
        }
    }

    /** A free variable declaration.
     *
     * This method do NOT handle those inside a function/method/namespace.
     */
    void put(ref const(VarDeclResult) result) {
        Nullable!USRType file_usr = addFileNode(streamed_nodes, recv, result.location);
        addVarDecl(file_usr, result);
    }

    /** A free variable declaration in a namespace.
     *
     * TODO maybe connect the namespace to the file?
     */
    void put(ref const(VarDeclResult) result, CppNs[] ns)
    in {
        assert(ns.length > 0);
    }
    body {
        auto ns_usr = addNamespaceNode(streamed_nodes, recv, ns);
        addVarDecl(ns_usr, result);
    }

    private void addVarDecl(Nullable!USRType parent, ref const(VarDeclResult) result) {
        { // instance node
            auto node = NodeVariable(result.instanceUSR, result.name,
                    result.type, decideColor(result), result.location);
            nodeIfMissing(streamed_nodes, recv, result.instanceUSR, NodeData(NodeData.Tag(node)));
        }

        if (!parent.isNull) {
            // connect namespace to instance
            addEdge(streamed_edges, recv, parent, result.instanceUSR);
        }

        // type node
        if (!result.type.kind.isPrimitive(lookup)) {
            auto node = NodeType(result.type, result.location);
            putToCache(NodeData(NodeData.Tag(node)));
            addEdge(streamed_edges, recv, result.instanceUSR, result.type.kind.usr);
        }
    }

    /** Accessing a global.
     *
     * Assuming that src is already put in the cache.
     * Assuming that target is already in cache or will be in the future when
     * traversing the AST.
     * */
    void put(ref const(TypeKindAttr) src, ref const(VarDeclResult) result) {
        addEdge(streamed_edges, recv, src.kind.usr, result.instanceUSR);
    }

    ///
    void put(ref const(FunctionDeclResult) result) {
        import std.algorithm : map, filter, joiner;
        import std.range : only, chain;
        import cpptooling.data.representation : unpackParam;

        auto src = result.type;

        {
            auto node = NodeFunction(src.kind.usr,
                    result.type.toStringDecl(result.name), result.name, result.location);
            putToCache(NodeData(NodeData.Tag(node)));
        }

        // dfmt off
        foreach (target; chain(only(cast(TypeKindAttr) result.returnType),
                               result.params
                                .map!(a => a.unpackParam)
                                .filter!(a => !a.isVariadic)
                                .map!(a => a.type)
                                .map!(a => resolvePointeeType(a.kind, a.attr, lookup))
                                .joiner
                                .map!(a => TypeKindAttr(a.kind, TypeAttr.init)))) {
            putToCache(NodeData(NodeData.Tag(NodeType(target))));
            edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
        }
        // dfmt on
    }

    /** Calls from src to result.
     *
     * Assuming that src is already put in the cache.
     *
     * Only interested in the relation from src to the function.
     */
    void put(ref const(TypeKindAttr) src, ref const(FunctionDeclResult) result) {
        // TODO investigate if the resolve is needed. I don't think so.
        auto target = resolveCanonicalType(result.type.kind, result.type.attr, lookup).front;

        auto node = NodeFunction(result.type.kind.usr,
                result.type.toStringDecl(result.name), result.name, result.location);
        putToCache(NodeData(NodeData.Tag(node)));

        edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
    }

    /** The node_cache may contain class/struct that have been put there by a parameter item.
     * Therefor bypass the cache when a definition is found.
     */
    void put(ref const(RecordResult) result, CppNs[] ns, NodeRecord in_node) {
        auto node = in_node;

        if (node.identifier.length == 0) {
            // a C typedef.
            // e.g. typedef struct { .. } Foo;
            auto type = resolveCanonicalType(result.type.kind, result.type.attr, lookup).front;
            node.identifier = type.kind.toStringDecl(TypeAttr.init);
        }

        if (result.type.attr.isDefinition) {
            node.location = result.location;
            nodeIfMissing(streamed_nodes, recv, result.type.kind.usr,
                    NodeData(NodeData.Tag(node)));
        } else {
            putToCache(NodeData(NodeData.Tag(node)));
        }

        auto ns_usr = addNamespaceNode(streamed_nodes, recv, ns);
        if (!ns_usr.isNull) {
            addEdge(streamed_edges, recv, ns_usr, result.type);
        }
    }

    /// Create relations to the parameters of a constructor.
    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result, in CppAccess access) {
        import std.algorithm : map, filter, joiner;
        import cpptooling.data.representation : unpackParam;

        // dfmt off
        foreach (target; result.params
            .map!(a => a.unpackParam)
            .filter!(a => !a.isVariadic)
            .map!(a => resolvePointeeType(a.type.kind, a.type.attr, lookup))
            .joiner
            .map!(a => TypeKindAttr(a.kind, TypeAttr.init))) {
            if (!target.kind.isPrimitive(lookup)) {
                putToCache(NodeData(NodeData.Tag(NodeType(target))));
                addEdge(streamed_edges, recv, result.type.kind.usr, target.kind.usr);
            }
        }
        // dfmt on
    }

    /// No parameters in a destructor so skipping.
    void put(ref const(TypeKindAttr) src, ref const(DestructorResult) result, in CppAccess access) {
        // do nothing
    }

    /// Create relations to the parameters of a method.
    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess access) {
        import std.algorithm : map, filter, joiner;
        import std.range : only, chain;
        import cpptooling.data.representation : unpackParam;

        // dfmt off
        foreach (target; chain(only(cast(TypeKindAttr) result.returnType),
                                   result.params
                                    .map!(a => a.unpackParam)
                                    .filter!(a => !a.isVariadic)
                                    .map!(a => resolvePointeeType(a.type.kind, a.type.attr, lookup))
                                    .joiner)
                        .map!(a => TypeKindAttr(a.kind, TypeAttr.init))) {
            if (!target.kind.isPrimitive(lookup)) {
                putToCache(NodeData(NodeData.Tag(NodeType(target))));
                addEdge(streamed_edges, recv, result.type.kind.usr, target.kind.usr);
            }
        }
        // dfmt on
    }

    /** Relation of a class/struct's field to the it is an instance of type.
     *
     * The field node is aggregated, and thus handled, in the NodeRecord.
     */
    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess access) {
        if (result.type.kind.isPrimitive(lookup)) {
            return;
        }

        auto target = resolvePointeeType(result.type.kind, result.type.attr, lookup).front;

        if (!target.kind.isPrimitive(lookup)) {
            putToCache(NodeData(NodeData.Tag(NodeType(target))));
            addEdge(streamed_edges, recv, result.instanceUSR, target.kind.usr);
        }
    }

    /// Avoid code duplication by creating nodes via the node_cache.
    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
        putToCache(NodeData(NodeData.Tag(NodeType(result.type))));
        // by definition it can never be a primitive type so no check needed.
        addEdge(streamed_edges, recv, src.kind.usr, result.canonicalUSR, EdgeKind.Generalization);
    }

private:

    import std.range : ElementType;

    /** Used for callback to distinguish the type of location that has been
     * resolved.
     */
    struct LocationCallback {
        void delegate(ref const(NodeData) type, ref const(LocationTag) loc) @safe unknown;
        void delegate(ref const(NodeData) type, ref const(LocationTag) loc) @safe declaration;
        void delegate(ref const(NodeData) type, ref const(LocationTag) loc) @safe definition;
    }

    /** Resolve a type and its location.
     *
     * Performs a callback to either:
     *  - callback_def with the resolved type:s TypeKindAttr for the type and
     *    location of the definition.
     *  - callback_decl with the resolved type:s TypeKindAttr.
     * */
    static void resolveLocation(Range, LookupT)(LocationCallback callback,
            Range range, LookupT lookup)
            if (is(Unqual!(ElementType!Range) == NodeData) && __traits(hasMember,
                LookupT, "kind") && __traits(hasMember, LookupT, "location")) {
        import std.algorithm : map;
        import std.typecons : tuple;

        // dfmt off
        foreach (ref a; range
                 // a tuple of (NodeData, DeclLocation)
                 .map!(a => tuple(a, lookup.location(a.usr)))) {
            // no location?
            if (a[1].length == 0) {
                LocationTag noloc;
                callback.unknown(a[0], noloc);
            }

            auto loc = a[1].front;

            if (loc.hasDefinition) {
                callback.definition(a[0], loc.definition);
            } else if (loc.hasDeclaration) {
                callback.declaration(a[0], loc.declaration);
            } else {
                // no location?
                LocationTag noloc;
                callback.unknown(a[0], noloc);
            }
        }
        // dfmt on
    }

    static auto toRelativePath(const LocationTag loc) {
        import std.path : relativePath;

        if (loc.kind == LocationTag.Kind.noloc) {
            return loc;
        }

        string rel;
        () @trusted{ rel = relativePath(loc.file); }();

        return LocationTag(Location(rel, loc.line, loc.column));
    }

    void putToCache(const NodeData data) {
        // lower the number of allocations by checking in the hash table.
        if (data.usr in streamed_nodes) {
            return;
        }

        node_cache.put(data);
    }

    // The following functions result in xml data being written.

    static Nullable!USRType addNamespaceNode(NodeStoreT, RecvT)(ref NodeStoreT nodes,
            ref RecvT recv, CppNs[] ns) {
        if (ns.length == 0) {
            return Nullable!USRType();
        }

        import cpptooling.data.type : toStringNs;

        auto ns_usr = USRType(ns.toStringNs);
        auto node = NodeData(NodeData.Tag(NodeNamespace(ns_usr)));
        nodeIfMissing(nodes, recv, ns_usr, node);

        return Nullable!USRType(ns_usr);
    }

    static USRType addFileNode(NodeStoreT, RecvT, LocationT)(ref NodeStoreT nodes,
            ref RecvT recv, LocationT location) {
        auto file_usr = cast(USRType) location.file;

        if (file_usr !in nodes) {
            auto node = NodeData(NodeData.Tag(NodeFile(file_usr)));
            nodeIfMissing(nodes, recv, file_usr, node);
        }

        return file_usr;
    }

    /**
     * Params:
     *   nodes = a AA with USRType as key
     *   recv = the receiver of the xml data
     *   node_usr = the unique USR for the node
     *   node = either the TypeKindAttr of the node or a type supporting
     *          `.toString` taking a generic writer as argument.
     */
    static void nodeIfMissing(NodeStoreT, RecvT, NodeT)(ref NodeStoreT nodes,
            ref RecvT recv, USRType node_usr, NodeT node) {
        if (node_usr in nodes) {
            return;
        }

        node.toString(recv, FormatSpec!char("%s"));
        nodes[node_usr] = true;
    }

    static bool isEitherPrimitive(LookupT)(TypeKindAttr t0, TypeKindAttr t1, LookupT lookup) {
        if (t0.kind.info.kind == TypeKind.Info.Kind.null_
                || t1.kind.info.kind == TypeKind.Info.Kind.null_
                || t0.kind.isPrimitive(lookup) || t1.kind.isPrimitive(lookup)) {
            return true;
        }

        return false;
    }

    static void edgeIfNotPrimitive(EdgeStoreT, RecvT, LookupT)(ref EdgeStoreT edges,
            ref RecvT recv, TypeKindAttr src, TypeKindAttr target, LookupT lookup) {
        if (isEitherPrimitive(src, target, lookup)) {
            return;
        }

        addEdge(edges, recv, src, target);
    }

    static void addEdge(EdgeStoreT, RecvT, SrcT, TargetT)(ref EdgeStoreT edges,
            ref RecvT recv, SrcT src, TargetT target, EdgeKind kind = EdgeKind.Directed) {
        string target_usr;
        static if (is(Unqual!TargetT == TypeKindAttr)) {
            if (target.kind.info.kind == TypeKind.Info.Kind.null_) {
                return;
            }

            target_usr = cast(string) target.kind.usr;
        } else {
            target_usr = cast(string) target;
        }

        string src_usr;
        static if (is(Unqual!SrcT == TypeKindAttr)) {
            src_usr = cast(string) src.kind.usr;
        } else {
            src_usr = cast(string) src;
        }

        // skip self edges
        if (target_usr == src_usr) {
            return;
        }

        // naive approach
        USRType edge_key = USRType(src_usr ~ "_" ~ target_usr);
        if (edge_key in edges) {
            return;
        }

        xmlEdge(recv, src_usr, target_usr, kind);
        edges[edge_key] = true;
    }
}

private mixin template NodeLocationMixin() {
    LocationTag location;

    @Attr(IdT.url) void url(scope StreamChar stream) {
        if (location.kind == LocationTag.Kind.loc) {
            ccdataWrap(stream, location.file);
        }
    }

    @Attr(IdT.position) void position(scope StreamChar stream) {
        import std.conv : to;

        if (location.kind == LocationTag.Kind.loc) {
            ccdataWrap(stream, "Line:", location.line.to!string, " Column:",
                    location.column.to!string);
        }
    }
}

/// Helper to generate a unique ID for the node.
private mixin template NodeIdMixin() {
    @NodeId void putId(scope StreamChar stream) {
        auto id = ValidNodeId(usr);
        id.toString(stream, FormatSpec!char("%s"));
    }

    debug {
        @NodeExtra void putIdDebug(scope StreamChar stream) {
            import std.format : formattedWrite;
            import std.string : replace;

            // printing the raw identifiers to make it easier to debug
            formattedWrite(stream, "<!-- id: %s -->", usr.replace("-", "_"));
        }
    }
}

/// A node for a free function or a class/struct method.
private @safe struct NodeFunction {
    import std.array : Appender;

    USRType usr;
    @Attr(IdT.signature) string signature;
    string identifier;

    mixin NodeLocationMixin;

    @Attr(IdT.kind) enum kind = "function";

    @Attr(IdT.nodegraphics) void graphics(scope StreamChar stream) {
        auto style = makeShapeNode(identifier, ColorKind.func);
        style.toString(stream, FormatSpec!char("%s"));
    }

    mixin NodeIdMixin;
}

@("Should be a xml node of a function")
unittest {
    auto func = NodeFunction(USRType("123"), "void foo(int)", "foo", LocationTag("fun.h", 1, 2));

    auto buf = appender!string();
    auto recv = DummyRecv(&buf);

    nodeToXml(func, recv);
    buf.data.shouldEqual(`<node id="18446744072944306312"><data key="d11"><![CDATA[void foo(int)]]></data><data key="d3"><![CDATA[fun.h]]></data><data key="d8"><![CDATA[Line:1 Column:2]]></data><data key="d9"><![CDATA[function]]></data><data key="d5"><y:ShapeNode><y:Geometry height="20" width="140"/><y:Fill color="#FF6600" transparent="false"/><y:NodeLabel autoSizePolicy="node_size" configuration="CroppingLabel"><![CDATA[foo]]></y:NodeLabel></y:ShapeNode></data><!-- id: 123 --></node>
`);
}

/// Represents either a class or struct.
private @safe struct NodeRecord {
    import std.array : Appender;

    USRType usr;
    string identifier;
    StereoType stereotype;
    Appender!(NodeField[]) attributes;
    Appender!(NodeFunction[]) methods;
    Appender!(NodeType[]) types;

    mixin NodeLocationMixin;

    @Attr(IdT.kind) enum kind = "record";

    @Attr(IdT.nodegraphics) void graphics(scope StreamChar stream) {
        //TODO express stereotype in some way
        auto folder = FolderNode(identifier);
        folder.toString(stream, FormatSpec!char("%s"));
    }

    @NodeAttribute string yfile = `yfiles.foldertype="folder"`;

    @NodeExtra void graph(scope StreamChar stream) {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        formattedWrite(stream, "\n" ~ `<graph edgedefault="directed" id="G%s:">` ~ "\n",
                nextGraphId);

        foreach (type; types.data) {
            nodeToXml(type, stream);
        }

        foreach (attr; attributes.data) {
            nodeToXml(attr, stream);
        }

        foreach (func; methods.data) {
            nodeToXml(func, stream);
        }

        put(stream, `</graph>`);
    }

    mixin NodeIdMixin;
}

/// Node for a C++ type that has no other suitable node to represent it.
private @safe struct NodeType {
    USRType usr;
    TypeKindAttr type;

    mixin NodeLocationMixin;

    this(TypeKindAttr type, LocationTag location) {
        this.type = type;
        this.location = location;

        this.usr = type.kind.usr;
    }

    this(TypeKindAttr type) {
        this(type, LocationTag(null));
    }

    @Attr(IdT.kind) enum kind = "type";

    @Attr(IdT.typeAttr) void typeAttr(scope StreamChar stream) {
        ccdataWrap(stream, type.attr.toString());
    }

    @Attr(IdT.signature) void signature(scope StreamChar stream) {
        ccdataWrap(stream, type.toStringDecl);
    }

    @Attr(IdT.nodegraphics) void graphics(scope StreamChar stream) {
        auto style = makeShapeNode(type.kind.toStringDecl(TypeAttr.init));
        style.toString(stream, FormatSpec!char("%s"));
    }

    @NodeId void putId(scope StreamChar stream) {
        auto id = ValidNodeId(type.kind.usr);
        id.toString(stream, FormatSpec!char("%s"));
    }
}

/// A variable definition.
private @safe struct NodeVariable {
    USRType usr;
    string identifier;
    TypeKindAttr type;
    ColorKind color;

    mixin NodeLocationMixin;

    @Attr(IdT.kind) enum kind = "variable";

    @Attr(IdT.signature) void signature(scope StreamChar stream) {
        ccdataWrap(stream, type.toStringDecl(identifier));
    }

    @Attr(IdT.typeAttr) void typeAttr(scope StreamChar stream) {
        ccdataWrap(stream, type.attr.toString());
    }

    @Attr(IdT.nodegraphics) void graphics(scope StreamChar stream) {
        auto style = makeShapeNode(identifier, color);
        style.toString(stream, FormatSpec!char("%s"));
    }

    mixin NodeIdMixin;
}

/// A node for a field of a class/struct.
private @safe struct NodeField {
    import cpptooling.data.type : AccessType;

    USRType usr;
    string identifier;
    TypeKindAttr type;
    AccessType access;
    ColorKind color;

    mixin NodeLocationMixin;

    @Attr(IdT.kind) enum kind = "field";

    @Attr(IdT.signature) void signature(scope StreamChar stream) {
        ccdataWrap(stream, type.toStringDecl(identifier));
    }

    @Attr(IdT.typeAttr) void typeAttr(scope StreamChar stream) {
        ccdataWrap(stream, type.attr.toString());
    }

    @Attr(IdT.nodegraphics) void graphics(scope StreamChar stream) {
        auto style = makeShapeNode(access.toInternal!string ~ identifier, color);
        style.toString(stream, FormatSpec!char("%s"));
    }

    mixin NodeIdMixin;
}

/// A node for a file.
private @safe struct NodeFile {
    USRType usr;

    @Attr(IdT.kind) enum kind = "file";

    @Attr(IdT.url) void url(scope StreamChar stream) {
        ccdataWrap(stream, cast(string) usr);
    }

    @Attr(IdT.signature) void signature(scope StreamChar stream) {
        ccdataWrap(stream, cast(string) usr);
    }

    @Attr(IdT.nodegraphics) void graphics(scope StreamChar stream) {
        import std.path : baseName;

        auto style = makeShapeNode((cast(string) usr).baseName, ColorKind.file);
        style.toString(stream, FormatSpec!char("%s"));
    }

    mixin NodeIdMixin;
}

/** A node for a namespace.
 *
 * Intended to enable edges of types and globals to relate to the namespace
 * that contain them.
 *
 * It is not intended to "contain" anything, which would be hard in for a
 * language as C++. Hard because any translation unit can add anything to a
 * namespace.
 */
private @safe struct NodeNamespace {
    USRType usr;

    @Attr(IdT.kind) enum kind = "namespace";

    @Attr(IdT.signature) void signature(scope StreamChar stream) {
        ccdataWrap(stream, cast(string) usr);
    }

    @Attr(IdT.nodegraphics) void graphics(scope StreamChar stream) {
        auto style = makeShapeNode(cast(string) usr, ColorKind.namespace);
        style.toString(stream, FormatSpec!char("%s"));
    }

    mixin NodeIdMixin;
}
