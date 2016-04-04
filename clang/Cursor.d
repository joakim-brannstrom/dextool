/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg, Joakim Brännström (joakim.brannstrom dottli gmx.com)
 * Version: 1.1+
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 * History:
 *  1.0 initial release. 2012-01-29 $(BR)
 *    Jacob Carlborg
 *
 *  1.1+ additional features missing compared to cindex.py. 2015-03-07 $(BR)
 *    Joakim Brännström
 */
module clang.Cursor;

import deimos.clang.index;

import clang.File;
import clang.SourceLocation;
import clang.SourceRange;
import clang.Type;
import clang.TranslationUnit;
import clang.Token;
import clang.Util;
import clang.Visitor;

/** The Cursor class represents a reference to an element within the AST. It
 * acts as a kind of iterator.
 *
 * Keep track of TranslationUnit the cursor belong to for correct
 * tokenization. The TranslationUnit returned from
 * clang_Cursor_getTranslationUnit do not produce correct tokens.
 */
struct Cursor {
    mixin CX;

    // for example primitive types are predefined
    private static const CXCursorKind[string] predefined;

    static this() {
        // populate the database once
        predefined = queryPredefined();
    }

    /// Retrieve the NULL cursor, which represents no entity.
    @property static Cursor empty() {
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
    @property string usr() const {
        return toD(clang_getCursorUSR(cx));
    }

    /// Return: Retrieve a name for the entity referenced by this cursor.
    @property string spelling() const {
        return toD(clang_getCursorSpelling(cx));
    }

    /**
     * Returns the storage class for a function or variable declaration.
     *
     * If the passed in Cursor is not a function or variable declaration,
     * CX_SC_Invalid is returned else the storage class.
     */
    @property CX_StorageClass storageClass() const {
        return clang_Cursor_getStorageClass(cx);
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
    @property string displayName() const {
        return toD(clang_getCursorDisplayName(cx));
    }

    /** Retrieve the string representing the mangled name of the cursor.
     *
     * Only useful for cursors that are NOT declarations.
     */
    @property string mangling() const {
        return toD(clang_Cursor_getMangling(cx));
    }

    /// Return: the kind of this cursor.
    @property CXCursorKind kind() const @trusted {
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
    @property SourceLocation location() const {
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
    @property Type type() @trusted const {
        auto r = clang_getCursorType(cx);
        return Type(this, r);
    }

    /** Return the underlying type of a typedef declaration.
     *
     * If the current cursor is not a typedef an empty type is returned.
     *
     * Returns: the Type the typedef cursor is a declaration for.
     */
    @property Type typedefUnderlyingType() @trusted const {
        auto r = clang_getTypedefDeclUnderlyingType(cx);
        return Type(this, r);
    }

    /** If the cursor is a reference to a declaration or a declaration of
     *  some entity, return a cursor that points to the definition of that
     *  entity.
     */
    @property Cursor definition() const {
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
    @property Cursor semanticParent() const {
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
    @property Cursor lexicalParent() const {
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
    @property Cursor referenced() const {
        auto r = clang_getCursorReferenced(cx);
        return Cursor(r);
    }

    @property DeclarationVisitor declarations() const {
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
    @property SourceRange extent() const @trusted {
        auto r = clang_getCursorExtent(cx);
        return SourceRange(r);
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
    @property Cursor canonical() @trusted const {
        auto r = clang_getCanonicalCursor(cx);
        return Cursor(r);
    }

    /// Determine the "language" of the entity referred to by a given cursor.
    @property CXLanguageKind language() const {
        return clang_getCursorLanguage(cx);
    }

    /// Returns: the translation unit that a cursor originated from.
    @property TranslationUnit translationUnit() const {
        return TranslationUnit(clang_Cursor_getTranslationUnit(cx));
    }

    /** Obtain Token instances formulating that compose this Cursor.
     *
     * This is a generator for Token instances. It returns all tokens which
     * occupy the extent this cursor occupies.
     *
     * Returns: A RefCounted TokenGroup.
     */
    @property auto tokens() const {
        import std.algorithm.mutation : stripRight;

        CXToken* tokens = null;
        uint numTokens = 0;
        clang_tokenize(translationUnit.cx, extent.cx, &tokens, &numTokens);
        auto result = TokenRange(translationUnit, tokens, numTokens);

        // For some reason libclang returns some tokens out of cursors extent.cursor
        return result.stripRight!(token => !intersects(extent, token.extent));
    }

    @property ObjcCursor objc() {
        return ObjcCursor(this);
    }

    @property FunctionCursor func() {
        return FunctionCursor(this);
    }

    @property EnumCursor enum_() @trusted {
        return EnumCursor(this);
    }

    @property AccessCursor access() {
        return AccessCursor(this);
    }

    @property Visitor all() {
        return Visitor(this);
    }

    /** Array of all children of the cursor.
     *
     * Params:
     *  ignorePredefined = ignore cursors for primitive types.
     */
    @property Cursor[] children(bool ignorePredefined = false) {
        import std.array : appender;
        import std.stdio;

        Cursor[] result = [];
        auto app = appender(result);

        if (ignorePredefined && isTranslationUnit) {
            foreach (cursor, _; all) {
                if (!cursor.isPredefined)
                    app.put(cursor);
            }
        } else {
            foreach (cursor, _; all)
                app.put(cursor);
        }

        return app.data;
    }

    /// Determine whether two cursors are equivalent.
    equals_t opEquals(const ref Cursor cursor) const {
        return clang_equalCursors(cast(CXCursor) cursor.cx, cast(CXCursor) cx) != 0;
    }

    size_t toHash() const nothrow @trusted {
        //TODO i'm not sure this is a good solution... investigate.
        try {
            return clang_hashCursor(cast(CXCursor) cx);
        }
        catch (Exception ex) {
            return 0;
        }
    }

    /// Determine whether the given cursor kind represents a declaration.
    @property bool isDeclaration() const {
        return clang_isDeclaration(cx.kind) != 0;
    }

    /** Determine whether the given cursor kind represents a simple
     * reference.
     *
     * Note that other kinds of cursors (such as expressions) can also refer to
     * other cursors. Use clang_getCursorReferenced() to determine whether a
     * particular cursor refers to another entity.
     */
    @property bool isReference() const {
        return clang_isReference(cx.kind) != 0;
    }

    /// Determine whether the given cursor kind represents an expression.
    @property bool isExpression() const {
        return clang_isExpression(cx.kind) != 0;
    }

    /// Determine whether the given cursor kind represents a statement.
    @property bool isStatement() const {
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
    @property bool isAnonymous() const {
        return clang_Cursor_isAnonymous(cx) != 0;
    }

    /// Determine whether the given cursor kind represents an attribute.
    @property bool isAttribute() const {
        return clang_isAttribute(cx.kind) != 0;
    }

    /// Determine whether the given cursor kind represents an invalid cursor.
    @property bool isValid() const {
        // note that it checks for invalidity of the cursor, thus the inverse
        // is the return value.
        // Why this note?
        // I almost thought it was a bug that the check was == 0
        return !clang_isInvalid(cx.kind);
    }

    /// Determine whether the given cursor kind represents a translation unit.
    @property bool isTranslationUnit() const {
        return clang_isTranslationUnit(cx.kind) != 0;
    }

    /** Determine whether the given cursor represents a preprocessing
     * element, such as a preprocessor directive or macro instantiation.
     */
    @property bool isPreprocessing() const {
        return clang_isPreprocessing(cx.kind) != 0;
    }

    /** Determine whether the given cursor represents a currently unexposed
     * piece of the AST (e.g., CXCursor_UnexposedStmt).
     */
    @property bool isUnexposed() const {
        return clang_isUnexposed(cx.kind) != 0;
    }

    /// Return: if cursor is null/empty.
    @property bool isEmpty() const {
        return clang_Cursor_isNull(cx) != 0;
    }

    /** Returns true if the declaration pointed at by the cursor is also a
     * definition of that entity.
     */
    bool isDefinition() const {
        return clang_isCursorDefinition(cast(CXCursor) cx) != 0;
    }

    /// Returns: if the base class specified by the cursor with kind CX_CXXBaseSpecifier is virtual.
    @property bool isVirtualBase() const {
        return clang_isVirtualBase(cx) != 0;
    }

    bool isPredefined() const {
        auto xkind = usr in predefined;
        return xkind !is null && *xkind == kind;
    }

    private static CXCursorKind[string] queryPredefined() {
        import clang.Index;
        import clang.TranslationUnit;

        CXCursorKind[string] result;

        Index index = Index(false, false);
        TranslationUnit unit = TranslationUnit.parseString(index, "", []);

        foreach (cursor; unit.cursor.children)
            result[cursor.usr] = cursor.kind;

        return result;
    }

    public static string predefinedToString() {
        import std.algorithm : map, joiner;
        import std.ascii : newline;
        import std.conv : text;
        import std.string : leftJustifier;

        return predefined.byKeyValue().map!(a => leftJustifier(a.key, 50)
                .text ~ a.value.text).joiner(newline).text;
    }
}

struct ObjcCursor {
    Cursor cursor;
    alias cursor this;

    @property ObjCInstanceMethodVisitor instanceMethods() {
        return ObjCInstanceMethodVisitor(cursor);
    }

    @property ObjCClassMethodVisitor classMethods() {
        return ObjCClassMethodVisitor(cursor);
    }

    @property ObjCPropertyVisitor properties() {
        return ObjCPropertyVisitor(cursor);
    }

    @property Cursor superClass() {
        foreach (cursor, parent; TypedVisitor!(CXCursorKind.CXCursor_ObjCSuperClassRef)(cursor))
            return cursor;

        return Cursor.empty();
    }

    @property ObjCProtocolVisitor protocols() {
        return ObjCProtocolVisitor(cursor);
    }

    @property Cursor category() {
        assert(cursor.kind == CXCursorKind.CXCursor_ObjCCategoryDecl);

        foreach (c, _; TypedVisitor!(CXCursorKind.CXCursor_ObjCClassRef)(cursor))
            return c;

        assert(0, "This cursor does not have a class reference.");
    }
}

struct FunctionCursor {
    Cursor cursor;
    alias cursor this;

    /// Return: Retrieve the Type of the result for this Cursor.
    @property Type resultType() {
        auto r = clang_getCursorResultType(cx);
        return Type(cursor, r);
    }

    @property ParamVisitor parameters() {
        return ParamVisitor(cursor);
    }

    //TODO remove
    @property bool isVariadic() {
        return type.func.isVariadic;
    }

    /** Determine if a C++ member function or member function template is
     * pure virtual.
     */
    @property bool isPureVirtual() {
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
    @property bool isVirtual() {
        return clang_CXXMethod_isVirtual(cx) != 0;
    }

    /** Determine if a C++ member function or member function template is
     * declared 'const'.
     */
    @property bool isConst() {
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
    @property bool isDynamicCall() {
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
    @property auto accessSpecifier() {
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
    @property auto file() {
        auto r = clang_getIncludedFile(cx);
        return File(r);
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

    /// Return: if the underlying type is an enum.
    @property bool isUnderlyingTypeEnum() {
        auto t = typedefUnderlyingType.declaration.enum_;
        return t.kind == CXTypeKind.CXType_Enum;
    }

    /// Return: if the type of the enum is signed.
    @property bool isSigned() @trusted {
        Type t;

        if (isUnderlyingTypeEnum) {
            t = typedefUnderlyingType.declaration.enum_.type;
        } else {
            t = Type(cursor, clang_getCursorType(cx));
        }

        with (CXTypeKind) switch (t.kind) {
        case CXType_Char_U:
        case CXType_UChar:
        case CXType_Char16:
        case CXType_Char32:
        case CXType_UShort:
        case CXType_UInt:
        case CXType_ULong:
        case CXType_ULongLong:
        case CXType_UInt128:
            return false;
        default:
            return true;
        }
    }
}

import std.array : appender, Appender;

string dump(ref Cursor c) {
    import std.conv : to;
    import std.string;

    static string stripPrefix(string x) {
        immutable string prefix = "CXCursor_";
        immutable size_t prefixSize = prefix.length;
        return x.startsWith(prefix) ? x[prefixSize .. $] : x;
    }

    static string prettyTokens(ref Cursor c, size_t limit = 5) {
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

    auto text = "%s \"%s\" [%d..%d] %s %s".format(stripPrefix(to!string(c.kind)),
            c.spelling, c.extent.start.offset, c.extent.end.offset, prettyTokens(c), c.usr);

    return text;
}

void dumpAST(ref Cursor c, ref Appender!string result, size_t indent, File* file) {
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
            if (!cursor.isPredefined() && cursor.location.file == *file)
                dumpAST(cursor, result, indent + step);
        }
    } else {
        foreach (cursor, _; c.all) {
            if (!cursor.isPredefined())
                cursor.dumpAST(result, indent + step);
        }
    }
}

void dumpAST(ref Cursor c, ref Appender!string result, size_t indent) {
    dumpAST(c, result, indent, null);
}

unittest {
    // "Should output the predefined types for inspection"
    import std.stdio;

    writeln(Cursor.predefinedToString);
}
