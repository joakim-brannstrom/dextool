/**
 * Copyright: Copyright (c) 2011-2016 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg, Joakim Brännström (joakim.brannstrom dottli gmx.com)
 * Version: 1.1+
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 * History:
 *  1.0 initial release. 2012-01-29 $(BR)
 *    Jacob Carlborg
 *
 *  1.1+ additional features missing compared to cindex.py. 2015-03-07 $(BR)
 *    Joakim Brännström
 *
 * TODO split the specific C++ stuff to a dedicated cursor.
 * TODO implement cxxMangling.
 */
module clang.Cursor;

import clang.c.Index;

import clang.Eval;
import clang.File;
import clang.SourceLocation;
import clang.SourceRange;
import clang.Token;
import clang.TranslationUnit;
import clang.Type;
import clang.Util;
import clang.Visitor;

/** The Cursor class represents a reference to an element within the AST. It
 * acts as a kind of iterator.
 */
@safe struct Cursor {
    mixin CX;

    /// Retrieve the NULL cursor, which represents no entity.
    @property static Cursor empty() @trusted {
        auto r = clang_getNullCursor();
        return Cursor(r);
    }

    /** Retrieve a Unified Symbol Resolution (USR) for the entity referenced by
     * the given cursor.
     *
     * A Unified Symbol Resolution (USR) is a string that identifies a
     * particular entity (function, class, variable, etc.) within a program.
     * USRs can be compared across translation units to determine, e.g., when
     * references in one translation refer to an entity defined in another
     * translation unit.
     */
    @property string usr() const @trusted scope {
        return toD(clang_getCursorUSR(cx));
    }

    /// Return: Retrieve a name for the entity referenced by this cursor.
    @property string spelling() const @trusted scope {
        return toD(clang_getCursorSpelling(cx));
    }

    /**
     * Returns the storage class for a function or variable declaration.
     *
     * If the passed in Cursor is not a function or variable declaration,
     * CX_SC_Invalid is returned else the storage class.
     */
    @property CX_StorageClass storageClass() const @trusted scope {
        return clang_Cursor_getStorageClass(cx);
    }

    /** Determine the linkage of the entity referred to by a given cursor.
     *
     * This value indicates that no linkage information is available for a
     * provided CXCursor.
     * CXLinkage_Invalid,
     *
     * This is the linkage for variables, parameters, and so on that have
     * automatic storage.  This covers normal (non-extern) local variables.
     * CXLinkage_NoLinkage,
     *
     * This is the linkage for static variables and static functions.
     * CXLinkage_Internal,
     *
     * This is the linkage for entities with external linkage that live
     * in C++ anonymous namespaces.
     * CXLinkage_UniqueExternal,
     *
     * This is the linkage for entities with true, external linkage.
     * CXLinkage_External
     */
    @property CXLinkageKind linkage() const @trusted scope {
        return clang_getCursorLinkage(cx);
    }

    /** Return the display name for the entity referenced by this cursor.
     *
     * The display name contains extra information that helps identify the
     * cursor, such as the parameters of a function or template or the
     * arguments of a class template specialization.
     *
     * If it is NOT a declaration then the return value is the same as
     * spelling.
     */
    @property string displayName() const @trusted scope {
        return toD(clang_getCursorDisplayName(cx));
    }

    /** Return the cursor kind of the template specialization that would be
     * generated when instantiating the template with this cursor.
     */
    @property CXCursorKind templateKind() const @trusted scope {
        return clang_getTemplateCursorKind(cx);
    }

    /** Return the cursor that represents the template that given cursor
     * specializes (or is instantiated) from.
     *
     * It will only work for a cursor that represent a specialization or
     * insantiation of a template. Otherwise, NULL cursor is returned.
     */
    @property CXCursor templateCursor() const @trusted scope {
        return clang_getSpecializedCursorTemplate(cx);
    }

    /** Determine the set of methods that are overridden by the given
     * method.
     *
     * In both Objective-C and C++, a method (aka virtual member function, in
     * C++) can override a virtual method in a base class. For Objective-C, a
     * method is said to override any method in the class's base class, its
     * protocols, or its categories' protocols, that has the same selector and
     * is of the same kind (class or instance). If no such method exists, the
     * search continues to the class's superclass, its protocols, and its
     * categories, and so on. A method from an Objective-C implementation is
     * considered to override the same methods as its corresponding method in
     * the interface.
     *
     * For C++, a virtual member function overrides any virtual member function
     * with the same signature that occurs in its base classes. With multiple
     * inheritance, a virtual member function can override several virtual
     * member functions coming from different base classes.
     *
     * In all cases, this function determines the immediate overridden method,
     * rather than all of the overridden methods. For example, if a method is
     * originally declared in a class A, then overridden in B (which in
     * inherits from A) and also in C (which inherited from B), then the only
     * overridden method returned from this function when invoked on C's method
     * will be B's method. The client may then invoke this function again,
     * given the previously-found overridden methods, to map out the complete
     * method-override set.
     */
    @property OverriddenSet overridden() const @trusted scope {
        CXCursor* overridden;
        uint num;
        clang_getOverriddenCursors(cx, &overridden, &num);
        return OverriddenSet(OverriddenSet.make(overridden), num);
    }

    /** Retrieve the string representing the mangled name of the cursor.
     *
     * Only useful for cursors that are NOT declarations.
     */
    @property string mangling() const @trusted scope {
        return toD(clang_Cursor_getMangling(cx));
    }

    /**
     * \brief Retrieve the CXStrings representing the mangled symbols of the C++
     * constructor or destructor at the cursor.
     */
    //@property string[] cxxMangling() const @trusted {
    //    CXStringSet *clang_Cursor_getCXXManglings(CXCursor);
    //}

    /// Return: the kind of this cursor.
    @property CXCursorKind kind() const @trusted scope {
        return clang_getCursorKind(cx);
    }

    /** Retrieve the physical location of the source constructor referenced by
     * the given cursor.
     *
     * The location of a declaration is typically the location of the name of
     * that declaration, where the name of that declaration would occur if it
     * is unnamed, or some keyword that introduces that particular declaration.
     * The location of a reference is where that reference occurs within the
     * source code.
     */
    @property SourceLocation location() const @trusted scope {
        return SourceLocation(clang_getCursorLocation(cx));
    }

    /** Type (if any) of the entity pointed at by the cursor.
     *
     * The following isDeclaration cursors are handled:
     *  - TypeDecl
     *  - DeclaratorDecl (if source info exist)
     *
     * isReference cursors may be automatically dereferenced if they are of the
     * following kind:
     *  - TypeRef
     *  - CXXBaseSpecifier
     *  - MemberRef
     *  - VariableRef
     * The following are NOT handled:
     *  - TemplateRef
     *  - NamespaceRef
     *  - OverloadedDeclRef
     */
    @property Type type() @trusted const scope {
        auto r = clang_getCursorType(cx);
        return Type(this, r);
    }

    /** Return the underlying type of a typedef declaration.
     *
     * If the current cursor is not a typedef an empty type is returned.
     *
     * Returns: the Type the typedef cursor is a declaration for.
     */
    @property Type typedefUnderlyingType() @trusted const scope {
        auto r = clang_getTypedefDeclUnderlyingType(cx);
        return Type(this, r);
    }

    /** If the cursor is a reference to a declaration or a declaration of
     *  some entity, return a cursor that points to the definition of that
     *  entity.
     */
    @property Cursor definition() const @trusted scope {
        auto r = clang_getCursorDefinition(cx);
        return Cursor(r);
    }

    /** Determine the semantic parent of the given cursor.
     *
     * The semantic parent of a cursor is the cursor that semantically contains
     * the given cursor. For many declarations, the lexical and semantic
     * parents are equivalent (the lexical parent is returned by
     * clang_getCursorLexicalParent()). They diverge when declarations or
     * definitions are provided out-of-line. For example:
     *
     * ---
     * class C {
     *  void f();
     * }
     *
     * void C::f() { }
     * ---
     *
     * In the out-of-line definition of C::f, the semantic parent is the the
     * class C, of which this function is a member. The lexical parent is the
     * place where the declaration actually occurs in the source code; in this
     * case, the definition occurs in the translation unit. In general, the
     * lexical parent for a given entity can change without affecting the
     * semantics of the program, and the lexical parent of different
     * declarations of the same entity may be different. Changing the semantic
     * parent of a declaration, on the other hand, can have a major impact on
     * semantics, and redeclarations of a particular entity should all have the
     * same semantic context.
     *
     * In the example above, both declarations of C::f have C as their semantic
     * context, while the lexical context of the first C::f is C and the
     * lexical context of the second C::f is the translation unit.
     *
     * For global declarations, the semantic parent is the translation unit.
     */
    @property Cursor semanticParent() const @trusted scope {
        auto r = clang_getCursorSemanticParent(cx);
        return Cursor(r);
    }

    /** Determine the lexical parent of the given cursor.
     *
     * The lexical parent of a cursor is the cursor in which the given cursor
     * was actually written. For many declarations, the lexical and semantic
     * parents are equivalent (the semantic parent is returned by
     * clang_getCursorSemanticParent()). They diverge when declarations or
     * definitions are provided out-of-line. For example:
     *
     * ---
     * class C {
     *  void f();
     * }
     *
     * void C::f() { }
     * ---
     *
     * In the out-of-line definition of C::f, the semantic parent is the the
     * class C, of which this function is a member. The lexical parent is the
     * place where the declaration actually occurs in the source code; in this
     * case, the definition occurs in the translation unit. In general, the
     * lexical parent for a given entity can change without affecting the
     * semantics of the program, and the lexical parent of different
     * declarations of the same entity may be different. Changing the semantic
     * parent of a declaration, on the other hand, can have a major impact on
     * semantics, and redeclarations of a particular entity should all have the
     * same semantic context.
     *
     * In the example above, both declarations of C::f have C as their semantic
     * context, while the lexical context of the first C::f is C and the
     * lexical context of the second \c C::f is the translation unit.
     *
     * For declarations written in the global scope, the lexical parent is
     * the translation unit.
     */
    @property Cursor lexicalParent() const @trusted scope {
        auto r = clang_getCursorLexicalParent(cx);
        return Cursor(r);
    }

    /** For a cursor that is a reference, retrieve a cursor representing the
     * entity that it references.
     *
     * Reference cursors refer to other entities in the AST. For example, an
     * Objective-C superclass reference cursor refers to an Objective-C class.
     * This function produces the cursor for the Objective-C class from the
     * cursor for the superclass reference. If the input cursor is a
     * declaration or definition, it returns that declaration or definition
     * unchanged.  Otherwise, returns the NULL cursor.
     */
    @property Cursor referenced() const @trusted scope {
        auto r = clang_getCursorReferenced(cx);
        return Cursor(r);
    }

    @property DeclarationVisitor declarations() const @trusted scope {
        return DeclarationVisitor(this);
    }

    /** Retrieve the physical extent of the source construct referenced by the
     * given cursor.
     *
     * The extent of a cursor starts with the file/line/column pointing at the
     * first character within the source construct that the cursor refers to
     * and ends with the last character withinin that source construct. For a
     * declaration, the extent covers the declaration itself. For a reference,
     * the extent covers the location of the reference (e.g., where the
     * referenced entity was actually used).
     */
    @property SourceRange extent() const @trusted scope {
        auto r = clang_getCursorExtent(cx);
        return SourceRange(r);
    }

    /** If cursor is a statement declaration tries to evaluate the statement
     * and if its variable, tries to evaluate its initializer, into its
     * corresponding type.
     */
    Eval eval() const @trusted {
        return Eval(clang_Cursor_Evaluate(cx));
    }

    /** Retrieve the canonical cursor corresponding to the given cursor.
     *
     * In the C family of languages, many kinds of entities can be declared
     * several times within a single translation unit. For example, a structure
     * type can be forward-declared (possibly multiple times) and later
     * defined:
     *
     * ---
     * struct X;
     * struct X;
     * struct X {
     *   int member;
     * }
     * ---
     *
     * The declarations and the definition of X are represented by three
     * different cursors, all of which are declarations of the same underlying
     * entity. One of these cursor is considered the "canonical" cursor, which
     * is effectively the representative for the underlying entity. One can
     * determine if two cursors are declarations of the same underlying entity
     * by comparing their canonical cursors.
     *
     * Return: The canonical cursor for the entity referred to by the given cursor.
     */
    @property Cursor canonical() @trusted const scope {
        auto r = clang_getCanonicalCursor(cx);
        return Cursor(r);
    }

    /// Determine the "language" of the entity referred to by a given cursor.
    @property CXLanguageKind language() const @trusted scope {
        return clang_getCursorLanguage(cx);
    }

    /// Returns: the translation unit that a cursor originated from.
    @property TranslationUnit translationUnit() const @trusted scope {
        return TranslationUnit(clang_Cursor_getTranslationUnit(cx));
    }

    /** Obtain Token instances formulating that compose this Cursor.
     *
     * This is a generator for Token instances. It returns all tokens which
     * occupy the extent this cursor occupies.
     *
     * Trusted: the API usage follows the LLVM manual. The potential problem
     * would be if clang_tokenize write back invalid addresses.
     *
     * Returns: A range over the tokens.
     */
    @property auto tokens() const @trusted scope {
        import std.algorithm.mutation : stripRight;

        CXToken* tokens = null;
        uint numTokens = 0;
        clang_tokenize(translationUnit.cx, extent.cx, &tokens, &numTokens);
        auto result = TokenRange(translationUnit, tokens, numTokens);

        // For some reason libclang returns some tokens out of cursors extent.cursor
        return result.stripRight!(token => !intersects(extent, token.extent));
    }

    @property FunctionCursor func() const return scope {
        return FunctionCursor(this);
    }

    @property EnumCursor enum_() const return scope {
        return EnumCursor(this);
    }

    @property AccessCursor access() const return scope {
        return AccessCursor(this);
    }

    @property IncludeCursor include() const return scope {
        return IncludeCursor(this);
    }

    @property Visitor all() const return scope {
        return Visitor(this);
    }

    private Cursor[] childrenImpl(T)(bool ignorePredefined) const scope @trusted {
        import std.array : appender;

        Cursor[] result;
        auto app = appender(result);

        if (ignorePredefined && isTranslationUnit) {
            foreach (cursor, _; T(this)) {
                app.put(cursor);
            }
        } else {
            foreach (cursor, _; T(this))
                app.put(cursor);
        }

        return app.data;
    }

    /** Array of all children of the cursor.
     *
     * Params:
     *  ignorePredefined = ignore cursors for primitive types.
     */
    Cursor[] children(bool ignorePredefined = false) const scope {
        return childrenImpl!Visitor(ignorePredefined);
    }

    Cursor[] childrenInOrder(bool ignorePredefined = false) const scope {
        return childrenImpl!InOrderVisitor(ignorePredefined);
    }

    /// Determine whether two cursors are equivalent.
    equals_t opEquals(scope const Cursor cursor) const @trusted {
        return clang_equalCursors(cast(CXCursor) cursor.cx, cast(CXCursor) cx) != 0;
    }

    /// Compute a hash value for the given cursor.
    size_t toHash() const nothrow @trusted scope {
        //TODO i'm not sure this is a good solution... investigate.
        try {
            return clang_hashCursor(cast(CXCursor) cx);
        } catch (Exception ex) {
            return 0;
        }
    }

    /// Determine whether the given cursor has any attributes.
    @property bool hasAttributes() const @trusted scope {
        return clang_Cursor_hasAttrs(cx) != 0;
    }

    /// Determine whether the given cursor kind represents a declaration.
    @property bool isDeclaration() const @trusted scope {
        return clang_isDeclaration(cx.kind) != 0;
    }

    /** Determine whether the given cursor kind represents a simple
     * reference.
     *
     * Note that other kinds of cursors (such as expressions) can also refer to
     * other cursors. Use clang_getCursorReferenced() to determine whether a
     * particular cursor refers to another entity.
     */
    @property bool isReference() const @trusted scope {
        return clang_isReference(cx.kind) != 0;
    }

    /// Determine whether the given cursor kind represents an expression.
    @property bool isExpression() const @trusted scope {
        return clang_isExpression(cx.kind) != 0;
    }

    /// Determine whether the given cursor kind represents a statement.
    @property bool isStatement() const @trusted scope {
        return clang_isStatement(cx.kind) != 0;
    }

    /** Determine whether the given cursor represents an anonymous record
     * declaration.
     *
     * The cursor must be a declaration and either a struct or union.
     *
     * Determines whether this field is a representative for an anonymous
     * struct or union. Such fields are unnamed and are implicitly generated by
     * the implementation to store the data for the anonymous union or struct.
     *
     * If the following is declared inside a struct.
     *
     * Example:
     * ---
     * union {
     *     int x;
     *     char y;
     * };
     * ---
     */
    @property bool isAnonymous() const @trusted scope {
        return clang_Cursor_isAnonymous(cx) != 0;
    }

    /// Determine whether the given cursor kind represents an attribute.
    @property bool isAttribute() const @trusted scope {
        return clang_isAttribute(cx.kind) != 0;
    }

    int bitFieldWidth() const @trusted scope {
        return clang_getFieldDeclBitWidth(cast(CXCursor) cx);
    }

    bool isBitField() const @trusted scope {
        return clang_Cursor_isBitField(cast(CXCursor) cx) != 0;
    }

    /// Determine whether the given cursor kind represents an invalid cursor.
    @property bool isValid() const @trusted scope {
        // note that it checks for invalidity of the cursor, thus the inverse
        // is the return value.
        return !clang_isInvalid(cx.kind);
    }

    /// Determine whether the given cursor kind represents a translation unit.
    @property bool isTranslationUnit() const @trusted scope {
        return clang_isTranslationUnit(cx.kind) != 0;
    }

    /** Determine whether the given cursor represents a preprocessing
     * element, such as a preprocessor directive or macro instantiation.
     */
    @property bool isPreprocessing() const @trusted scope {
        return clang_isPreprocessing(cx.kind) != 0;

        // If clang_isPreprocessing isn't working out this is the
        // implementation from DStep.

        //CXCursorKind kind = clang_getCursorKind(cx);
        //return CXCursorKind.firstPreprocessing <= kind &&
        //    kind <= CXCursorKind.lastPreprocessing;
    }

    /** Determine whether the given cursor represents a currently unexposed
     * piece of the AST (e.g., CXCursor_UnexposedStmt).
     */
    @property bool isUnexposed() const @trusted scope {
        return clang_isUnexposed(cx.kind) != 0;
    }

    /// Return: if the underlying type is an enum.
    @property bool isUnderlyingTypeEnum() const @trusted scope {
        auto underlying = typedefUnderlyingType;
        if (!underlying.isValid) {
            return false;
        }

        auto decl = underlying.declaration;
        if (!decl.isValid) {
            return false;
        }

        return decl.type.isEnum;
    }

    /// Return: if cursor is null/empty.
    @property bool isEmpty() const @trusted scope {
        return clang_Cursor_isNull(cx) != 0;
    }

    /** Returns true if the declaration pointed at by the cursor is also a
     * definition of that entity.
     */
    bool isDefinition() const @trusted scope {
        return clang_isCursorDefinition(cast(CXCursor) cx) != 0;
    }

    /// Returns: if the base class specified by the cursor with kind CX_CXXBaseSpecifier is virtual.
    @property bool isVirtualBase() const @trusted scope {
        return clang_isVirtualBase(cx) != 0;
    }

    /** Determine whether a CXCursor that is a macro, is function like.
     */
    bool isMacroFunctionLike() const @trusted scope {
        return clang_Cursor_isMacroFunctionLike(cx) != 0;
    }

    /** Determine whether a CXCursor that is a macro, is a builtin one.
     */
    bool isMacroBuiltin() const @trusted scope {
        return clang_Cursor_isMacroBuiltin(cx) != 0;
    }

    /** Determine whether a CXCursor that is a function declaration, is an
     * inline declaration.
     */
    bool isFunctionInlined() const @trusted scope {
        return clang_Cursor_isFunctionInlined(cx) != 0;
    }

    /// Determine if a C++ constructor is a converting constructor.
    bool isConvertingConstructor() const @trusted scope {
        return clang_CXXConstructor_isConvertingConstructor(cx) != 0;
    }

    /// Determine if a C++ constructor is a copy constructor.
    bool isCopyConstructor() const @trusted scope {
        return clang_CXXConstructor_isCopyConstructor(cx) != 0;
    }

    /// Determine if a C++ constructor is the default constructor.
    bool isDefaultConstructor() const @trusted scope {
        return clang_CXXConstructor_isDefaultConstructor(cx) != 0;
    }

    /// Determine if a C++ constructor is a move constructor.
    bool isMoveConstructor() const @trusted scope {
        return clang_CXXConstructor_isMoveConstructor(cx) != 0;
    }

    /// Determine if a C++ field is declared 'mutable'.
    bool isMutable() const @trusted scope {
        return clang_CXXField_isMutable(cx) != 0;
    }

    /// Determine if a C++ method is declared '= default'.
    bool isDefaulted() const @trusted scope {
        return clang_CXXMethod_isDefaulted(cx) != 0;
    }

    /// Determine if a C++ member function or member function template is pure virtual.
    bool isPureVirtual() @trusted scope {
        return clang_CXXMethod_isPureVirtual(cx) != 0;
    }

    /** Describe the visibility of the entity referred to by a cursor.
     *
     * Note: This is linker visibility.
     *
     * This returns the default visibility if not explicitly specified by
     * a visibility attribute. The default visibility may be changed by
     * commandline arguments.
     *
     * Params:
     *  cursor The cursor to query.
     *
     * Returns: The visibility of the cursor.
     */
    CXVisibilityKind visibility() const @trusted {
        return clang_getCursorVisibility(cx);
    }
}

struct FunctionCursor {
    Cursor cursor;
    alias cursor this;

    /// Return: Retrieve the Type of the result for this Cursor.
    @property Type resultType() @trusted {
        auto r = clang_getCursorResultType(cx);
        return Type(cursor, r);
    }

    @property ParamVisitor parameters() {
        return ParamVisitor(cursor);
    }

    /** Determine if a C++ member function or member function template is
     * pure virtual.
     */
    @property bool isPureVirtual() @trusted {
        return clang_CXXMethod_isPureVirtual(cx) != 0;
    }

    /** Returns: True if the cursor refers to a C++ member function or member
     * function template that is declared 'static'.
     */
    @property bool isStatic() @trusted {
        return clang_CXXMethod_isStatic(cx) != 0;
    }

    /** Determine if a C++ member function or member function template is
     * explicitly declared 'virtual' or if it overrides a virtual method from
     * one of the base classes.
     */
    @property bool isVirtual() @trusted {
        return clang_CXXMethod_isVirtual(cx) != 0;
    }

    /** Determine if a C++ member function or member function template is
     * declared 'const'.
     */
    @property bool isConst() @trusted {
        return clang_CXXMethod_isConst(cx) != 0;
    }

    /** Given a cursor pointing to a C++ method call or an Objective-C
     * message, returns non-zero if the method/message is "dynamic", meaning:
     *
     * For a C++ method: the call is virtual.
     * For an Objective-C message: the receiver is an object instance, not 'super'
     * or a specific class.
     *
     * If the method/message is "static" or the cursor does not point to a
     * method/message, it will return zero.
     */
    @property bool isDynamicCall() @trusted {
        return clang_Cursor_isDynamicCall(cx) != 0;
    }
}

struct AccessCursor {
    Cursor cursor;
    alias cursor this;

    /** Returns the access control level for the C++ base specifier represented
     * by a cursor with kind CXCursor_CXXBaseSpecifier or
     * CXCursor_AccessSpecifier.
     */
    @property auto accessSpecifier() @trusted scope const {
        return clang_getCXXAccessSpecifier(cx);
    }
}

struct ParamCursor {
    Cursor cursor;
    alias cursor this;
}

struct IncludeCursor {
    Cursor cursor;
    alias cursor this;

    /** Retrieve the file that is included by the given inclusion directive
     * cursor.
     */
    @property auto file() @trusted {
        return File(clang_getIncludedFile(cx));
    }
}

struct EnumCursor {
    import std.conv : to;

    Cursor cursor;
    alias cursor this;

    @property string value() @safe {
        import std.conv : to;

        return to!string(signedValue);
    }

    /** Retrieve the integer type of an enum declaration.
     *
     * If the cursor does not reference an enum declaration, an invalid type is
     * returned.
     */
    @property Type type() @trusted {
        auto r = clang_getEnumDeclIntegerType(cx);
        return Type(cursor, r);
    }

    /** Retrieve the integer value of an enum constant declaration as a signed
     * long.
     *
     * If the cursor does not reference an enum constant declaration, LLONG_MIN
     * is returned.  Since this is also potentially a valid constant value, the
     * kind of the cursor must be verified before calling this function.
     */
    @property long signedValue() @trusted {
        return clang_getEnumConstantDeclValue(cx);
    }

    /** Retrieve the integer value of an enum constant declaration as an
     * unsigned long.
     *
     * If the cursor does not reference an enum constant declaration,
     * ULLONG_MAX is returned.  Since this is also potentially a valid constant
     * value, the kind of the cursor must be verified before calling this
     * function.
     */
    @property ulong unsignedValue() @trusted {
        return clang_getEnumConstantDeclUnsignedValue(cx);
    }

    /// Return: if the type of the enum is signed.
    @property bool isSigned() const @trusted {
        Type t;

        if (isUnderlyingTypeEnum) {
            t = typedefUnderlyingType.declaration.enum_.type;
        } else {
            t = Type(cursor, clang_getCursorType(cx));
        }

        return t.isSigned;
    }
}

struct OverriddenSet {
    import std.typecons : RefCounted;

    private struct Container {
        CXCursor* overridden;
        ~this() {
            if (overridden != null)
                clang_disposeOverriddenCursors(overridden);
        }
    }

    private RefCounted!Container data;
    private CXCursor[] overridden;

    static private RefCounted!Container make(CXCursor* overridden) {
        RefCounted!Container rval;
        rval.overridden = overridden;
        return rval;
    }

    private this(RefCounted!Container data, uint numOverloads) {
        this.data = data;
        this.overridden = data.overridden[0 .. numOverloads];
    }

    bool empty() const { return overridden.length == 0; }

    CXCursor front() { return overridden[0]; }

    void popFront() {
        overridden = overridden[1..$];
    }

    size_t length() const { return overridden.length; }
}

import std.array : appender, Appender;

string dump(ref const(Cursor) c) @trusted {
    import std.conv : to;
    import std.string;

    static string stripPrefix(string x) {
        immutable string prefix = "CXCursor_";
        immutable size_t prefixSize = prefix.length;
        return x.startsWith(prefix) ? x[prefixSize .. $] : x;
    }

    static string prettyTokens(ref const(Cursor) c, size_t limit = 5) {
        import std.algorithm.comparison : min;

        TokenRange tokens = c.tokens;

        string prettyToken(Token token) {
            immutable string prefix = "CXToken_";
            immutable size_t prefixSize = prefix.length;
            auto x = to!string(token.kind);
            return "%s \"%s\"".format(x.startsWith(prefix) ? x[prefixSize .. $] : x, token.spelling);
        }

        auto result = appender!string("[");

        if (tokens.length != 0) {
            result.put(prettyToken(tokens[0]));

            foreach (Token token; c.tokens[1 .. min($, limit)]) {
                result.put(", ");
                result.put(prettyToken(token));
            }
        }

        if (tokens.length > limit)
            result.put(", ..]");
        else
            result.put("]");

        return result.data;
    }

    auto text = "%s \"%s\" [%d:%d..%d:%d] %s %s".format(stripPrefix(to!string(c.kind)),
            c.spelling, c.extent.start.line, c.extent.start.column,
            c.extent.end.line, c.extent.end.column, prettyTokens(c), c.usr);

    return text;
}

void dumpAST(ref const(Cursor) c, ref Appender!string result, size_t indent, File* file) @trusted {
    import std.ascii : newline;
    import std.format;
    import std.array : replicate;

    immutable size_t step = 4;

    auto text = dump(c);

    result.put(" ".replicate(indent));
    result.put(text);
    result.put(newline);

    if (file) {
        foreach (cursor, _; c.all) {
            if (cursor.location.file == *file)
                dumpAST(cursor, result, indent + step);
        }
    } else {
        foreach (cursor, _; c.all) {
            cursor.dumpAST(result, indent + step);
        }
    }
}

void dumpAST(ref const(Cursor) c, ref Appender!string result, size_t indent) @safe {
    dumpAST(c, result, indent, null);
}
