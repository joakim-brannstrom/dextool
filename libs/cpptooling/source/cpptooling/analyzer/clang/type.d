/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Version: Initial created: Jan 30, 2012
Copyright (c) 2012 Jacob Carlborg. All rights reserved.

# Interaction flow
Pass1, implicit anonymous struct and unions.
Pass2, struct or union decl who has no name.
Pass3, anonymous instantiated types.
Pass4, generic, last decision point for deriving data from the cursor.
PassType, derive type from the cursors type.

# Location information
The "source" location is only, always the definition.
Declarations are "using" locations.

## CS101 refresher.
A definition is the information needed to create an instance of the type.

A declaration is a subset of the information that makes it possible to use in most scenarios.
The most telling example of an useful declaration is a function declaration, "void foo();".
Useful most everywhere.
But during linking it must be defined _somewhere_ or a linker error will ensue.

# Future optimization
 - Skip the primitive types by having them prepoulated in the Container.
 - Minimize the amoung of data that is propagated by changing TypeResults to
    ensure only unique USR's exist in it.
 - Skip pass4+ if the USR already exist in the container.
*/
module cpptooling.analyzer.clang.type;

import std.algorithm : among;
import std.conv : to;
import std.range : only;
import std.string : format;
import std.traits;
import std.typecons : Flag, Yes, No, Tuple, Nullable;
import logger = std.experimental.logger;

import clang.c.Index : CXTypeKind, CXCursorKind;
import clang.Cursor : Cursor;
import clang.Type : Type;

import my.sumtype;
import my.optional;

import libclang_ast.cursor_logger : logNode;

public import cpptooling.data.kind_type;
import cpptooling.analyzer.clang.type_logger : logType;
import cpptooling.data : SimpleFmt, TypeId, TypeIdLR;
import cpptooling.data : Location, LocationTag;
import cpptooling.data.symbol : Container, USRType;

private string nextSequence() @safe {
    import std.conv : text;
    import cpptooling.utility.global_unique : nextNumber;

    return text(nextNumber);
}

/// Returns: Filter node to only return those that are a typeref.
private auto filterByTypeRef(T)(auto ref T in_) {
    import std.algorithm : filter;

    return in_.filter!(a => a.isTypeRef);
}

///
private bool isTypeRef(Cursor c) {
    // CXCursorKind.CXCursor_TypeRef is the first node, thus >=...
    // it is not in any other way "special".

    return c.kind >= CXCursorKind.CXCursor_TypeRef && c.kind <= CXCursorKind.CXCursor_LastRef;
}

/** Iteratively try to construct a USR that is reproducable from the cursor.
 *
 * Only use when c.usr may return the empty string.
 *
 * Fallback case, using location to make it unique.
 *
 * strategy 1
 *  try and derive a location from the lexical parent.
 * strategy 2
 *  handled by putBacktrackLocation when loc_.kind is null_.
 *  putBacktrackLocation will then use nextSequence to generate a _for sure_
 *  unique ID.
 */
private void makeFallbackUSR(Writer)(scope Writer w, scope const Cursor c, in uint this_indent) @safe {
    // strategy 1
    auto loc_ = backtrackLocation(c);

    // strategy 2
    putBacktrackLocation(w, c, loc_);
}

/// ditto
/// Returns: fallback USR from the cursor.
private USRType makeFallbackUSR(const Cursor c, in uint this_indent) @safe
out (result) {
    logger.trace(result, this_indent);
    assert(result.length > 0);
}
do {
    import std.array : appender;

    auto app = appender!string();
    makeFallbackUSR((const(char)[] s) { app.put(s); }, c, this_indent);

    return USRType(app.data);
}

/// Make a USR, never failing.
USRType makeEnsuredUSR(scope const Cursor c, in uint this_indent) @safe
out (result) {
    logger.trace(result, this_indent);
    assert(result.length > 0);
}
do {
    import std.array : appender;

    auto usr = USRType(c.usr);
    if (usr.length > 0) {
        return usr;
    }

    auto app = appender!string();
    makeFallbackUSR((const(char)[] s) { app.put(s); }, c, this_indent);
    app.put("§");
    app.put(nextSequence);

    return USRType(app.data);
}

private void assertTypeResult(const ref TypeResults results) @trusted {
    void assert_(const TypeResult result) {
        assert(result.type.toStringDecl("x").length > 0);
        assert(result.type.kind.usr.length > 0);

        result.type.kind.info.match!(ignore!(TypeKind.PrimitiveInfo), (_) {
            if (result.location.kind != LocationTag.Kind.noloc) {
                assert(result.location.file.length > 0);
            }
        });
    }

    assert_(results.primary);

    foreach (ref result; results.extra) {
        assert_(result);
    }
}

struct BacktrackLocation {
    static import clang.SourceLocation;
    import my.optional;
    static import cpptooling.data.type;

    alias Tag = Optional!(cpptooling.data.type.Location);

    Tag tag;

    /// Number of nodes backtracked through until a valid was found
    int backtracked;
}

/** Lexical backtrack from the argument cursor to first cursor with a valid
 * location.
 *
 * using a for loop to ensure it is NOT an infinite loop.
 * hoping 100 is enough for all type of nesting to reach at least translation
 * unit.
 *
 * Return: Location and nr of backtracks needed.
 */
private BacktrackLocation backtrackLocation(scope const Cursor c) @trusted {
    import cpptooling.data.type : Location;

    BacktrackLocation rval;

    Cursor parent = c;
    for (rval.backtracked = 0; !rval.tag.hasValue && rval.backtracked < 100; ++rval.backtracked) {
        auto loc = parent.location;
        auto spell = loc.spelling;
        if (spell.file is null) {
            // do nothing
        } else if (spell.file.name.length != 0) {
            rval.tag = some(Location(spell.file.name, spell.line, spell.column));
        } else if (parent.isTranslationUnit) {
            rval.tag = some(Location(spell.file.name, spell.line, spell.column));
            break;
        }

        parent = () @trusted { return parent.lexicalParent; }();
    }

    return rval;
}

/// TODO consider if .offset should be used too. But may make it harder to
/// reverse engineer a location.
private void putBacktrackLocation(Writer)(scope Writer app, scope const Cursor c,
        BacktrackLocation back_loc) @safe {
    import std.range.primitives : put;

    static import cpptooling.data.type;

    // using a suffix that do NOT exist in the clang USR standard.
    // TODO lookup the algorithm for clang USR to see if $ is valid.
    enum marker = '§';

    app.put(back_loc.tag.orElse(Location(nextSequence)).toString);

    put(app, marker);
    put(app, back_loc.backtracked.to!string);
    if (c.isValid) {
        put(app, () @trusted { return c.spelling; }());
    }
}

LocationTag makeLocation(const Cursor c) @safe
out (result) {
    import std.utf : validate;

    validate(result.file);
}
do {
    import std.array : appender;

    auto loc = c.location.spelling;
    auto rval = Location(loc.file.name, loc.line, loc.column);

    if (rval.file.length > 0) {
        return LocationTag(rval);
    }

    auto loc_ = backtrackLocation(c);

    if (!loc_.tag.hasValue) {
        return LocationTag(null);
    }

    auto app = appender!string();
    putBacktrackLocation((const(char)[] s) { app.put(s); }, c, loc_);

    rval = Location(app.data, loc.line, loc.column);

    return LocationTag(rval);
}

TypeAttr makeTypeAttr(ref Type type, const Cursor c) {
    TypeAttr attr;

    attr.isConst = cast(Flag!"isConst") type.isConst;
    attr.isRef = cast(Flag!"isRef")(type.kind == CXTypeKind.CXType_LValueReference);
    attr.isPtr = cast(Flag!"isPtr")(type.kind == CXTypeKind.CXType_Pointer);
    attr.isArray = cast(Flag!"isArray") type.isArray;
    attr.isDefinition = cast(Flag!"isDefinition") c.isDefinition;

    return attr;
}

TypeKindAttr makeTypeKindAttr(ref Type type, const Cursor c) {
    TypeKindAttr tka;
    tka.attr = makeTypeAttr(type, c);

    return tka;
}

TypeKindAttr makeTypeKindAttr(ref Type type, ref TypeKind tk, const Cursor c) {
    auto tka = makeTypeKindAttr(type, c);
    tka.kind = tk;

    return tka;
}

/** Deduct the type the node represents.
 *
 * pass 1, implicit anonymous structs and unions.
 * pass 2, implicit types aka no spelling exist for them.
 * pass 3, instansiated anonymous types and typedef of anonymous.
 * pass 4, normal nodes, typedefs and references.
 * passType, collect type information. The final result in most cases.
 *
 * TODO add "in" to parameter c.
 *
 * Params:
 *  c = cursor to retrieve from.
 *  container = container holding type symbols.
 *  indent = ?
 */
Nullable!TypeResults retrieveType(scope const Cursor c, ref Container container, in uint indent = 0)
in {
    logNode(c, indent);

    // unable to derive anything useful from a typeref when based on nothing else.
    // __va_list is an examle (found in stdarg.h).
    if (indent == 0 && isRefNode(c.kind)) {
        assert(false);
    }
}
out (result) {
    logTypeResult(result, indent);

    // ensure no invalid data is returned
    if (!result.isNull && indent == 0) {
        assertTypeResult(result.get);
    }
}
do {
    Nullable!TypeResults rval;

    // bail early
    if (c.kind.among(CXCursorKind.CXCursor_MacroDefinition)) {
        return rval;
    }

    foreach (pass; only(&pass1, &pass2, &pass3)) {
        auto r = pass(c, indent + 1);
        if (!r.isNull) {
            rval = typeof(return)(TypeResults(r.get, null));
            return rval;
        }
    }

    rval = pass4(c, container, indent + 1);
    return rval;
}

/** Pass 1, implicit anonymous types for struct and union.
 *
 * TODO merge with pass2. Code duplication
 */
private Nullable!TypeResult pass1(scope const Cursor c, uint indent)
in {
    logNode(c, indent);
}
do {
    Nullable!TypeResult rval;

    if (!c.isAnonymous) {
        return rval;
    }

    switch (c.kind) with (CXCursorKind) {
    case CXCursor_StructDecl:
        goto case;
    case CXCursor_UnionDecl:
        auto type = c.type;
        rval = TypeResult();
        rval.get.type = makeTypeKindAttr(type, c);

        string spell = type.spelling;
        rval.get.type.kind.info = TypeKind.RecordInfo(SimpleFmt(TypeId(spell)));
        rval.get.type.kind.usr = USRType(c.usr);
        rval.get.location = makeLocation(c);
        break;
    default:
    }

    return rval;
}

/** Pass 2, detect anonymous types who has "no name".
 *
 * Only struct, enum, union can possibly have this attribute.
 * The types name.
 *
 * TODO consider using the identifier as the spelling.
 *
 * Example:
 * ---
 * struct (implicit name) { <-- and spelling is ""
 * } Struct;
 *
 * union (implicit name) { <-- and spelling is ""
 * } Union;
 *
 * typedef enum {
 *  X <--- this one
 * } Enum; <--- not this one, covered by "other" pass
 * ---
 */
private Nullable!TypeResult pass2(scope const Cursor c, uint indent)
in {
    logNode(c, indent);
}
do {
    Nullable!TypeResult rval;

    if (c.spelling.length != 0) {
        return rval;
    }

    switch (c.kind) with (CXCursorKind) {
    case CXCursor_StructDecl:
        goto case;
    case CXCursor_UnionDecl:
        auto type = c.type;
        rval = TypeResult(makeTypeKindAttr(type, c), LocationTag.init);
        rval.get.type.kind.info = TypeKind.RecordInfo(SimpleFmt(TypeId(nextSequence)));
        rval.get.type.kind.usr = USRType(c.usr);
        rval.get.location = makeLocation(c);
        break;
    case CXCursor_EnumDecl:
        auto type = c.type;
        rval = TypeResult(makeTypeKindAttr(type, c), LocationTag.init);
        rval.get.type.kind.info = TypeKind.SimpleInfo(SimpleFmt(TypeId(nextSequence)));
        rval.get.type.kind.usr = USRType(c.usr);
        rval.get.location = makeLocation(c);
        break;
    default:
    }

    return rval;
}

/** Detect anonymous types that have an instansiation.
 *
 * Continuation of Pass 2.
 * Kept separate from Pass 3 to keep the passes logically "small".
 * Less cognitive load to understand what the passes do.
 *
 * Examle:
 * ---
 * struct {
 * } Struct;
 * ---
 */
private Nullable!TypeResult pass3(scope const Cursor c, uint indent)
in {
    logNode(c, indent);
}
do {
    Nullable!TypeResult rval;

    switch (c.kind) with (CXCursorKind) {
    case CXCursor_FieldDecl:
        goto case;
    case CXCursor_VarDecl:
        import std.range : takeOne;

        foreach (child; c.children.takeOne) {
            rval = pass2(child, indent + 1);
        }
        break;
    default:
    }

    return rval;
}

/**
 */
private Nullable!TypeResults pass4(scope const Cursor c, ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    auto indent = this_indent + 1;
    Nullable!TypeResults rval;

    switch (c.kind) with (CXCursorKind) {
    case CXCursor_TypedefDecl:
        rval = retrieveTypeDef(c, container, indent);
        break;

    case CXCursor_TypeAliasTemplateDecl:
    case CXCursor_TypeAliasDecl:
        rval = retrieveTypeAlias(c, container, indent);
        break;

    case CXCursor_FieldDecl:
    case CXCursor_VarDecl:
        rval = retrieveInstanceDecl(c, container, indent);
        break;

    case CXCursor_ParmDecl:
        rval = retrieveParam(c, container, indent);
        break;

    case CXCursor_TemplateTypeParameter:
        rval = retrieveTemplateParam(c, container, indent);
        break;

    case CXCursor_ClassTemplatePartialSpecialization:
    case CXCursor_ClassTemplate:
        rval = retrieveClassTemplate(c, container, indent);
        break;

    case CXCursor_StructDecl:
    case CXCursor_UnionDecl:
    case CXCursor_ClassDecl:
    case CXCursor_EnumDecl:
        auto type = c.type;
        rval = passType(c, type, container, indent);
        break;

    case CXCursor_CXXMethod:
    case CXCursor_FunctionDecl:
        rval = retrieveFunc(c, container, indent);
        break;

    case CXCursor_Constructor:
        auto type = c.type;
        rval = typeToCtor(c, type, container, indent);
        break;

    case CXCursor_Destructor:
        auto type = c.type;
        rval = typeToDtor(c, type, indent);
        break;

    case CXCursor_IntegerLiteral:
        auto type = c.type;
        rval = passType(c, type, container, indent);
        break;

    case CXCursor_CXXBaseSpecifier:
        rval = retrieveClassBaseSpecifier(c, container, indent);
        break;

    case CXCursor_DeclRefExpr:
    case CXCursor_TypeRef:
    case CXCursor_TemplateRef:
    case CXCursor_NamespaceRef:
    case CXCursor_MemberRef:
    case CXCursor_LabelRef:
        auto refc = c.referenced;
        rval = retrieveType(refc, container, indent);
        break;

    case CXCursor_NoDeclFound:
        // nothing to do
        break;

    case CXCursor_NonTypeTemplateParameter:
        auto type = c.type;
        rval = typeToSimple(c, type, indent);
        break;

    case CXCursor_UnexposedDecl:
        rval = retrieveUnexposed(c, container, indent);
        if (rval.isNull) {
            logger.trace("Not implemented type retrieval for node ", c.usr);
        }
        break;

    default:
        // skip for now, may implement in the future
        logger.trace("Not implemented type retrieval for node ", c.usr);
    }

    return rval;
}

//TODO add comment, I don't understand what the function is intended to do from
// the function name.
private bool isUnexposedDeclWithUSR(CXCursorKind kind) {
    switch (kind) with (CXCursorKind) {
    case CXCursor_TypedefDecl:
    case CXCursor_TemplateTypeParameter:
    case CXCursor_ClassTemplate:
    case CXCursor_StructDecl:
    case CXCursor_UnionDecl:
    case CXCursor_ClassDecl:
    case CXCursor_EnumDecl:
        return true;
    default:
        return false;
    }
}

private bool canConvertNodeDeclToType(CXCursorKind kind) {
    switch (kind) with (CXCursorKind) {
    case CXCursor_TypedefDecl:
    case CXCursor_TemplateTypeParameter:
    case CXCursor_ClassTemplate:
    case CXCursor_StructDecl:
    case CXCursor_UnionDecl:
    case CXCursor_ClassDecl:
    case CXCursor_EnumDecl:
    case CXCursor_CXXMethod:
    case CXCursor_FunctionDecl:
    case CXCursor_Constructor:
    case CXCursor_Destructor:
    case CXCursor_IntegerLiteral:
        return true;
    default:
        return false;
    }
}

private bool isRefNode(CXCursorKind kind) {
    switch (kind) with (CXCursorKind) {
    case CXCursor_TypeRef:
    case CXCursor_CXXBaseSpecifier:
    case CXCursor_TemplateRef:
    case CXCursor_NamespaceRef:
    case CXCursor_MemberRef:
    case CXCursor_LabelRef:
        return true;
    default:
        return false;
    }
}

private Nullable!TypeResults retrieveUnexposed(const Cursor c,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind.among(CXCursorKind.CXCursor_UnexposedDecl,
            CXCursorKind.CXCursor_NonTypeTemplateParameter));
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    import std.range : takeOne;

    auto indent = this_indent + 1;
    Nullable!TypeResults rval;

    foreach (child; c.children.takeOne) {
        switch (child.kind) with (CXCursorKind) {
        case CXCursor_CXXMethod:
        case CXCursor_FunctionDecl:
            rval = pass4(child, container, indent);
            if (!rval.isNull) {
                // cases like typeof(x) y;
                // fix in the future
                rval.get.primary.type.kind.info.match!(ignore!(TypeKind.FuncInfo),
                        _ => rval.nullify);
            }
            break;

        default:
        }
    }

    return rval;
}

private Nullable!TypeResults passType(const Cursor c, ref Type type,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);

    //TODO investigate if the below assumption is as it should be.
    // Not suposed to be handled here.
    // A typedef cursor shall have been detected and then handled by inspecting the child.
    // MAYBE move primitive type detection here.
    //assert(type.kind != CXTypeKind.CXType_Typedef);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    import std.range : takeOne;

    auto indent = 1 + this_indent;
    Nullable!TypeResults rval;

    switch (type.kind) with (CXTypeKind) {
    case CXType_FunctionNoProto:
    case CXType_FunctionProto:
        rval = typeToFuncProto(c, type, container, indent);
        break;

    case CXType_BlockPointer:
        rval = typeToFuncPtr(c, type, container, indent);
        break;

        // handle ref and ptr the same way
    case CXType_LValueReference:
    case CXType_Pointer:
        //TODO fix architecture so this check isn't needed.
        //Should be possible to merge typeToFunPtr and typeToPointer
        if (type.isFunctionPointerType) {
            rval = typeToFuncPtr(c, type, container, indent);
        } else {
            rval = typeToPointer(c, type, container, indent);
        }
        break;

    case CXType_ConstantArray:
    case CXType_IncompleteArray:
        rval = typeToArray(c, type, container, indent);
        break;

    case CXType_Record:
        rval = typeToRecord(c, type, indent);
        break;

    case CXType_Typedef:
        // unable to represent a typedef as a typedef.
        // Falling back on representing as a Simple.
        // Note: the usr from the cursor is null.
        rval = typeToFallBackTypeDef(c, type, indent);
        break;

    case CXType_Unexposed:
        debug {
            logger.trace("Unexposed, investigate if any other action should be taken");
        }
        if (!c.kind.among(CXCursorKind.CXCursor_FunctionDecl, CXCursorKind.CXCursor_CXXMethod)) {
            // see retrieveUnexposed for why
            rval = typeToSimple(c, type, indent);
        } else if (type.isFunctionType) {
            rval = typeToFuncProto(c, type, container, indent);
        }
        break;

    default:
        rval = typeToSimple(c, type, indent);
    }

    return rval;
}

/** Create a representation of a typeRef for the cursor.
*/
private TypeResults typeToTypeRef(const Cursor c, ref Type type, USRType type_ref,
        USRType canonical_ref, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    const uint indent = this_indent + 1;
    string spell = type.spelling;

    // ugly hack
    if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
        spell = spell[6 .. $];
    }

    TypeKind.TypeRefInfo info;
    info.fmt = SimpleFmt(TypeId(spell));
    info.typeRef = type_ref;
    info.canonicalRef = canonical_ref;

    TypeResults rval;
    rval.primary.type.attr = makeTypeAttr(type, c);
    rval.primary.type.kind.info = info;

    // a typedef like __va_list has a null usr
    if (c.usr.length == 0) {
        rval.primary.type.kind.usr = makeFallbackUSR(c, indent);
    } else {
        rval.primary.type.kind.usr = c.usr;
    }

    rval.primary.location = makeLocation(c);

    return rval;
}

/** Use fallback strategy for typedef's via Simple.
 *
 * A typedef referencing a type that it isn't possible to derive information
 * from to correctly represent (pointer, record, primitive etc).
 *
 * The fall back strategy is in that case to represent the type textually as a Simple.
 * The TypeKind->typeRef then references this simple type.
 */
private Nullable!TypeResults typeToFallBackTypeDef(const Cursor c, ref Type type, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    string spell = type.spelling;

    // ugly hack to remove const
    if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
        spell = spell[6 .. $];
    }

    auto rval = makeTypeKindAttr(type, c);

    auto info = TypeKind.SimpleInfo(SimpleFmt(TypeId(spell)));
    rval.kind.info = info;

    // a typedef like __va_list has a null usr
    if (c.usr.length == 0) {
        rval.kind.usr = makeFallbackUSR(c, this_indent + 1);
    } else {
        rval.kind.usr = c.usr;
    }

    auto loc = makeLocation(c);

    return typeof(return)(TypeResults(TypeResult(rval, loc), null));
}

private Nullable!TypeResults typeToSimple(const Cursor c, ref Type type, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    auto rval = makeTypeKindAttr(type, c);
    LocationTag loc;

    auto maybe_primitive = translateCursorType(type.kind);

    if (maybe_primitive.isNull) {
        string spell = type.spelling;
        rval.kind.info = TypeKind.SimpleInfo(SimpleFmt(TypeId(spell)));

        rval.kind.usr = c.usr;
        if (rval.kind.usr.length == 0) {
            rval.kind.usr = makeFallbackUSR(c, this_indent + 1);
        }
        loc = makeLocation(c);
    } else {
        string spell = maybe_primitive.get;
        rval.kind.info = TypeKind.PrimitiveInfo(SimpleFmt(TypeId(spell)));

        rval.kind.usr = USRType(maybe_primitive.get);
        loc = LocationTag(null);
    }

    return typeof(return)(TypeResults(TypeResult(rval, loc), null));
}

/// A function proto signature?
/// Workaround by checking if the return type is valid.
private bool isFuncProtoTypedef(const Cursor c) {
    auto result_t = c.type.func.resultType;
    return result_t.isValid;
}

private Nullable!TypeResults typeToTypedef(const Cursor c, ref Type type,
        USRType typeRef, USRType canonicalRef, ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.kind.among(CXTypeKind.CXType_Typedef)
            || c.kind == CXCursorKind.CXCursor_TypeAliasTemplateDecl);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    /// Make a string that represent the type.
    static string makeSpelling(const Cursor c, ref Type type) {
        import std.array : array;
        import std.algorithm : canFind, map, joiner;
        import std.range : retro, chain, only;
        import std.utf : byChar;

        string spell = type.spelling;

        if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
            spell = spell[6 .. $];
        }

        if (!spell.canFind("::")) {
            // if it isn't contained in a namespace then perform a backtracking of
            // the scope to ensure it isn't needed.  Implicit struct or enums need
            // this check.
            // Example: typedef struct {} Struct;

            import cpptooling.analyzer.clang.cursor_backtrack : backtrackScopeRange;

            // dfmt off
            spell = cast(string) chain(only(spell), backtrackScopeRange(c).map!(a => a.spelling))
                .array
                .retro
                .joiner("::")
                .byChar
                .array;
            // dfmt on
        }

        return spell;
    }

    auto spell = makeSpelling(c, type);

    TypeKind.TypeRefInfo info;
    info.fmt = SimpleFmt(TypeId(spell));
    info.typeRef = typeRef;
    info.canonicalRef = canonicalRef;

    TypeResults rval;
    rval.primary.type.attr = makeTypeAttr(type, c);
    rval.primary.type.kind.info = info;

    // a typedef like __va_list has a null usr
    if (c.usr.length == 0) {
        rval.primary.type.kind.usr = makeFallbackUSR(c, this_indent + 1);
    } else {
        rval.primary.type.kind.usr = c.usr;
    }

    rval.primary.location = makeLocation(c);

    return typeof(return)(rval);
}

/** Make a Record from a declaration or definition.
 */
private Nullable!TypeResults typeToRecord(const Cursor c, ref Type type, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
    assert(type.kind == CXTypeKind.CXType_Record);
}
out (result) {
    logTypeResult(result, indent);
}
do {
    string spell = type.spelling;

    // ugly hack needed when canonicalType has been used to get the type of a
    // cursor
    if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
        spell = spell[6 .. $];
    }

    TypeKind.RecordInfo info;
    info.fmt = SimpleFmt(TypeId(spell));

    auto rval = makeTypeKindAttr(type, c);
    rval.kind.info = info;
    rval.kind.usr = c.usr;
    auto loc = makeLocation(c);

    if (rval.kind.usr.length == 0) {
        rval.kind.usr = makeFallbackUSR(c, indent + 1);
    }

    return typeof(return)(TypeResults(TypeResult(rval, loc), null));
}

/** Represent a pointer type hierarchy.
 *
 * Returns: TypeResults.primary.attr is the pointed at attribute.
 */
private Nullable!TypeResults typeToPointer(const Cursor c, ref Type type,
        ref Container container, const uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference));
}
out (result) {
    logTypeResult(result.get, this_indent);
    result.get.primary.type.kind.info.match!(ignore!(const TypeKind.FuncPtrInfo),
            ignore!(const TypeKind.PointerInfo), (_) { assert(0, "wrong type"); });
}
do {
    import cpptooling.data : PtrFmt, Left, Right;

    immutable indent = this_indent + 1;

    static auto getPointee(const Cursor c, ref Type type, ref Container container, in uint indent) {
        auto pointee = type.pointeeType;
        auto c_pointee = pointee.declaration;

        debug {
            logNode(c_pointee, indent);
            logType(pointee, indent);
        }

        TypeResults rval;

        // find the underlying type information
        if (c_pointee.kind == CXCursorKind.CXCursor_TypedefDecl) {
            rval = retrieveType(c_pointee, container, indent).get;
        } else if (pointee.kind == CXTypeKind.CXType_Unexposed) {
            pointee = type.canonicalType;
            while (pointee.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference)) {
                pointee = pointee.pointeeType;
            }
            rval = passType(c, pointee, container, indent).get;

            if (c_pointee.kind.isUnexposedDeclWithUSR) {
                rval.primary.type.kind.info.match!((TypeKind.RecordInfo t) {
                    // if the current pointers type is for a declaration use this
                    // usr instead of the one from pointee.
                    // Solves the case of a forward declared class in a namespace.
                    // The retrieved data is only correct if it is from the
                    // canonical type but the USR is wrong.
                    string usr = c_pointee.usr;
                    rval.primary.type.kind.usr = usr;

                    // TODO investigate if a usr null checking is needed.
                    // I think it is unnecessary but unsure at this point.
                    // It is possible to run a full scan of google mock and all
                    // internal tests without this check.
                    // If this hasn't been changed for 6 month remove this comment.
                    // Written at 2016-07-01, remove by 2017-02-01.
                }, (_) {});
            }
        } else if (c_pointee.kind == CXCursorKind.CXCursor_NoDeclFound) {
            while (pointee.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference)) {
                pointee = pointee.pointeeType;
            }

            auto c_decl = pointee.declaration;

            if (c_decl.kind == CXCursorKind.CXCursor_NoDeclFound) {
                // primitive types do not have a declaration cursor.
                // find the underlying primitive type.
                rval = passType(c, pointee, container, indent).get;
            } else {
                rval = retrieveType(c_decl, container, indent).get;
            }
        } else {
            rval = retrieveType(c_pointee, container, indent).get;
        }

        return rval;
    }

    auto pointee = getPointee(c, type, container, indent);

    auto attrs = retrievePointeeAttr(type, indent);

    TypeKind.PointerInfo info;
    info.pointee = pointee.primary.type.kind.usr;
    info.attrs = attrs.ptrs;

    pointee.primary.type.kind.info.match!((TypeKind.ArrayInfo t) {
        auto type_id = pointee.primary.type.kind.splitTypeId(indent);
        info.fmt = PtrFmt(TypeIdLR(Left(type_id.left ~ "("), Right(")" ~ type_id.right)));
    }, (_) { info.fmt = PtrFmt(pointee.primary.type.kind.splitTypeId(indent)); });

    TypeResults rval;
    rval.primary.type.kind.info = info;
    // somehow pointee.primary.attr is wrong, somehow. Don't undestand why.
    // TODO remove this hack
    rval.primary.type.attr = attrs.base;
    // a pointer is always itselfs definition because they are always unique
    rval.primary.type.attr.isDefinition = Yes.isDefinition;

    // must be unique even when analyzing many translation units.
    // Could maybe work if static/anonymous namespace influenced the USR.
    rval.primary.type.kind.usr = makeFallbackUSR(c, indent);
    rval.primary.location = makeLocation(c);

    rval.extra = [pointee.primary] ~ pointee.extra;

    return typeof(return)(rval);
}

/** Represent a function pointer type.
 *
 * Return: correct formatting and attributes for a function pointer.
 */
private Nullable!TypeResults typeToFuncPtr(const Cursor c, ref Type type,
        ref Container container, const uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference));
    assert(type.isFunctionPointerType);
}
out (result) {
    logTypeResult(result, this_indent);
    result.get.primary.type.kind.info.match!(restrictTo!(const TypeKind.CtorInfo,
            const TypeKind.DtorInfo, const TypeKind.RecordInfo,
            const TypeKind.SimpleInfo, const TypeKind.ArrayInfo, (val) {
            assert(0, "wrong type " ~ typeof(val).stringof);
        }), (_) {});
}
do {
    import cpptooling.data : FuncPtrFmt, Left, Right;

    immutable indent = this_indent + 1;

    // find the underlying function prototype
    auto pointee_type = type;
    while (pointee_type.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference)) {
        pointee_type = pointee_type.pointeeType;
    }
    debug {
        logType(pointee_type, indent);
    }

    auto attrs = retrievePointeeAttr(type, indent);
    auto pointee = typeToFuncProto(c, pointee_type, container, indent + 1);

    TypeKind.FuncPtrInfo info;
    info.pointee = pointee.get.primary.type.kind.usr;
    info.attrs = attrs.ptrs;
    info.fmt = () {
        auto tid = pointee.get.primary.type.kind.splitTypeId(indent);
        return FuncPtrFmt(TypeIdLR(Left(tid.left ~ "("), Right(")" ~ tid.right)));
    }();

    TypeResults rval;
    rval.primary.type.kind.info = info;
    rval.primary.type.kind.usr = makeFallbackUSR(c, indent);
    rval.primary.location = makeLocation(c);
    // somehow pointee.primary.attr is wrong, somehow. Don't undestand why.
    // TODO remove this hack
    rval.primary.type.attr = attrs.base;

    rval.extra = [pointee.get.primary] ~ pointee.get.extra;

    return typeof(return)(rval);
}

private Nullable!TypeResults typeToFuncProto(InfoT = TypeKind.FuncInfo)(
        const Cursor c, ref Type type, ref Container container, in uint this_indent)
        if (is(InfoT == TypeKind.FuncInfo) || is(InfoT == TypeKind.FuncSignatureInfo))
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.isFunctionType || type.isTypedef || type.kind == CXTypeKind.CXType_FunctionNoProto);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    import std.array : array;
    import std.algorithm : map;
    import std.string : strip;
    import cpptooling.data : FuncFmt, Left, Right, FuncSignatureFmt;

    const auto indent = this_indent + 1;

    // TODO redesign. This is brittle and ugly.
    // return by value instead of splitting two ways like this.
    TypeKindAttr retrieveReturn(ref TypeResults rval) {
        auto result_type = type.func.resultType;
        auto result_decl = result_type.declaration;
        debug {
            logNode(result_decl, indent);
            logType(result_type, indent);
        }

        auto this_node = passType(result_decl, result_type, container, indent + 1).get;

        if (result_decl.kind == CXCursorKind.CXCursor_NoDeclFound) {
            rval = this_node;
        } else {
            rval = retrieveType(result_decl, container, indent + 1).get;

            // use the attributes derived from this node because it is not
            // preserved in the result_decl. This is a problem when the return
            // type is a typedef.  The const attribute isn't preserved.
            rval.primary.type.attr = this_node.primary.type.attr;

            rval.extra ~= this_node.primary;
            rval.extra ~= this_node.extra;
        }

        return rval.primary.type;
    }

    TypeResults rval;
    TypeResults return_rval;

    auto return_t = retrieveReturn(return_rval);
    auto params = extractParams(c, type, container, indent);
    TypeResult primary;
    primary.type = makeTypeKindAttr(type, c);

    // a C++ member function must be queried for constness via a different API
    primary.type.attr.isConst = cast(Flag!"isConst") c.func.isConst;

    InfoT info;
    static if (is(InfoT == TypeKind.FuncInfo)) {
        info.fmt = FuncFmt(TypeIdLR(Left(return_t.toStringDecl.strip),
                Right("(" ~ params.params.joinParamId ~ ")")));
    } else {
        info.fmt = FuncSignatureFmt(TypeIdLR(Left(return_t.toStringDecl.strip),
                Right("(" ~ params.params.joinParamId ~ ")")));
    }
    info.return_ = return_t.kind.usr;
    info.returnAttr = return_t.attr;
    info.params = params.params.map!(a => FuncInfoParam(a.result.type.kind.usr,
            a.result.type.attr, a.id, a.isVariadic)).array();

    primary.type.kind.info = info;
    primary.location = makeLocation(c);

    primary.type.kind.usr = c.usr;
    if (primary.type.kind.usr.length == 0) {
        primary.type.kind.usr = makeFallbackUSR(c, indent);
    } else if (c.kind.among(CXCursorKind.CXCursor_VarDecl, CXCursorKind.CXCursor_FieldDecl,
            CXCursorKind.CXCursor_TemplateTypeParameter, CXCursorKind.CXCursor_ParmDecl)) {
        // TODO consider how the knowledge of the field could be "moved" out of
        // this function.
        // Instances must result in a unique USR. Otherwise it is impossible to
        // differentiate between the type and field.
        primary.type.kind.usr = makeFallbackUSR(c, indent);
    }

    rval.primary = primary;
    rval.extra ~= params.params.map!(a => a.result).array() ~ params.extra;
    rval.extra ~= return_rval.primary;
    rval.extra ~= return_rval.extra;

    return typeof(return)(rval);
}

private Nullable!TypeResults typeToCtor(const Cursor c, ref Type type,
        ref Container container, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
    assert(c.kind == CXCursorKind.CXCursor_Constructor);
}
out (result) {
    logTypeResult(result, indent);
}
do {
    import std.algorithm : map;
    import std.array : array;
    import cpptooling.data : CtorFmt;

    TypeResults rval;
    auto params = extractParams(c, type, container, indent);
    TypeResult primary;
    primary.type = makeTypeKindAttr(type, c);

    TypeKind.CtorInfo info;
    info.fmt = CtorFmt(TypeId(format("(%s)", params.params.joinParamId())));
    info.params = params.params.map!(a => FuncInfoParam(a.result.type.kind.usr,
            a.result.type.attr, a.id, a.isVariadic)).array();
    info.id = c.spelling;

    primary.type.kind.info = info;
    primary.type.kind.usr = c.usr;
    primary.location = makeLocation(c);

    rval.primary = primary;
    rval.extra ~= params.params.map!(a => a.result).array() ~ params.extra;

    return typeof(return)(rval);
}

private Nullable!TypeResults typeToDtor(const Cursor c, ref Type type, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
    assert(c.kind == CXCursorKind.CXCursor_Destructor);
}
out (result) {
    logTypeResult(result, indent);
}
do {
    TypeResults rval;
    auto primary = makeTypeKindAttr(type, c);

    TypeKind.DtorInfo info;
    info.id = c.spelling[1 .. $]; // remove the leading ~

    primary.kind.info = info;
    primary.kind.usr = c.usr;

    rval.primary.location = makeLocation(c);
    rval.primary.type = primary;

    return typeof(return)(rval);
}

//TODO change the array to an appender, less GC pressure
private alias PointerTypeAttr = Tuple!(TypeAttr[], "ptrs", TypeAttr, "base");

/** Retrieve the attributes of the pointers until base condition.
 *
 * [$] is the value pointed at.
 *
 * Params:
 *  underlying = the value type, injected at correct position.
 *  type = a pointer or reference type.
 *  indent = indent for the log strings.
 * Return: An array of attributes for the pointers.
 */
private PointerTypeAttr retrievePointeeAttr(ref Type type, in uint this_indent)
in {
    logType(type, this_indent);
}
out (result) {
    import std.range : chain, only;

    foreach (r; chain(only(result.base), result.ptrs)) {
        logTypeAttr(r, this_indent);
    }
}
do {
    auto indent = this_indent + 1;
    PointerTypeAttr rval;
    auto decl_c = type.declaration;

    if (type.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference)) {
        // recursive
        auto pointee = type.pointeeType;
        rval = retrievePointeeAttr(pointee, indent);
        // current appended so right most ptr is at position 0.
        rval.ptrs ~= makeTypeAttr(type, decl_c);
    } else {
        // Base condition.
        rval.base = makeTypeAttr(type, decl_c);
    }

    return rval;
}

/// TODO this function is horrible. Refactor
private Nullable!TypeResults typeToArray(const Cursor c, ref Type type,
        ref Container container, const uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
}
out (result) {
    logTypeResult(result.get, this_indent);
    result.get.primary.type.kind.info.match!(ignore!(const TypeKind.ArrayInfo), (_) {
        assert(0, "wrong type");
    });
}
do {
    import std.format : format;
    import cpptooling.data : ArrayFmt, LocationTag, Location;

    immutable indent = this_indent + 1;

    static void gatherIndexesToElement(Type start, ref ArrayInfoIndex[] indexes, ref Type element) {
        Type curr = start;

        while (curr.kind.among(CXTypeKind.CXType_ConstantArray, CXTypeKind.CXType_IncompleteArray)) {
            auto arr = curr.array;

            switch (curr.kind) with (CXTypeKind) {
            case CXType_ConstantArray:
                indexes ~= ArrayInfoIndex(arr.size);
                break;
            case CXType_IncompleteArray:
                indexes ~= ArrayInfoIndex();
                break;
            default:
                break;
            }

            curr = arr.elementType;
        }

        element = curr;
    }

    static void determineElement(Type ele_type, ref ArrayInfoIndex[] indexes, const Cursor c, ref Container container,
            ref USRType primary_usr, ref LocationTag primary_loc,
            ref TypeResults element, const uint indent) {
        auto index_decl = ele_type.declaration;

        if (index_decl.kind == CXCursorKind.CXCursor_NoDeclFound) {
            // on purpuse not checking if it is null before using
            element = passType(c, ele_type, container, indent).get;

            if (element.primary.type.kind.usr.length != 0) {
                primary_usr = element.primary.type.kind.usr;
            } else {
                primary_usr = makeFallbackUSR(c, indent);
            }
            primary_loc = element.primary.location;
        } else {
            // on purpuse not checking if it is null before using
            element = retrieveType(index_decl, container, indent).get;

            primary_usr = element.primary.type.kind.usr;
            primary_loc = element.primary.location;
        }
        // let the indexing affect the USR as to not collide with none-arrays of
        // the same type.
        primary_usr = primary_usr ~ indexes.toRepr;

        switch (primary_loc.kind) {
        case LocationTag.Kind.noloc:
            // TODO this is stupid ... fix it. Shouldn't be needed but happens
            // when it is an array of primary types.
            // Probably the correct fix is the contract in retrieveType to check
            // that if it is an array at primary types it do NOT check for length.
            primary_loc = makeLocation(c);
            break;
        default:
        }
    }

    // step 1, find indexing and element type
    ArrayInfoIndex[] index_nr;
    Type element_type = type;

    gatherIndexesToElement(type, index_nr, element_type);

    // step 2, determine element
    TypeResults element;
    USRType primary_usr;
    LocationTag primary_loc;

    determineElement(element_type, index_nr, c, container, primary_usr,
            primary_loc, element, indent);

    // step 3, put together the result

    TypeKind.ArrayInfo info;
    info.element = element.primary.type.kind.usr;
    info.indexes = index_nr;
    info.fmt = ArrayFmt(element.primary.type.kind.splitTypeId(indent));

    TypeResults rval;

    if (element.primary.type.kind.info.match!(restrictTo!(TypeKind.PointerInfo,
            TypeKind.FuncPtrInfo, val => false), _ => true)) {
        auto elem_t = type.array.elementType;
        auto decl_c = elem_t.declaration;
        rval.primary.type.attr = makeTypeAttr(elem_t, decl_c);
    } else {
        rval.primary.type.attr = element.primary.type.attr;
    }

    rval.primary.type.kind.usr = primary_usr;
    rval.primary.location = primary_loc;
    rval.primary.type.kind.info = info;
    rval.extra ~= [element.primary] ~ element.extra;

    return typeof(return)(rval);
}

/** Retrieve the type of an instance declaration.
 *
 * Questions to consider:
 *  - Is the type a typeref?
 *  - Is it a function pointer?
 *  - Is the type a primitive type?
 */
private Nullable!TypeResults retrieveInstanceDecl(const Cursor c,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    with (CXCursorKind) {
        assert(c.kind.among(CXCursor_VarDecl, CXCursor_FieldDecl,
                CXCursor_TemplateTypeParameter, CXCursor_ParmDecl));
    }
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    import std.range : takeOne;

    const indent = this_indent + 1;
    auto c_type = c.type;

    auto handlePointer(ref Nullable!TypeResults rval) {
        switch (c_type.kind) with (CXTypeKind) {
            // Is it a pointer?
            // Then preserve the pointer structure but dig deeper for the
            // pointed at type.
        case CXType_LValueReference:
        case CXType_Pointer:
            // must retrieve attributes from the pointed at type thus need a
            // more convulated deduction
            rval = passType(c, c_type, container, indent);
            foreach (tref; c.children.takeOne) {
                auto child = retrieveType(tref, container, indent);
                if (!child.isNull) {
                    rval.get.extra ~= [child.get.primary] ~ child.get.extra;
                }
            }
            break;

        default:
        }
    }

    auto handleTypedef(ref Nullable!TypeResults rval) {
        import std.algorithm : until;
        import libclang_ast.cursor_visitor : visitBreathFirst;

        // example of tree analyzed:
        // VarDecl -> TypedefDecl
        // VarDecl -> TypeRef -> TypedefDecl
        foreach (child; c.visitBreathFirst.until!(a => a.depth == 3)) {
            if (child.kind == CXCursorKind.CXCursor_TypeRef) {
                rval = retrieveType(child, container, indent);
                break;
            } else if (child.kind == CXCursorKind.CXCursor_TypedefDecl) {
                rval = retrieveType(child, container, indent);
                break;
            }
        }

        if (!rval.isNull) {
            // depend on the underlying cursor
            auto old_def = rval.get.primary.type.attr.isDefinition;
            rval.get.primary.type.attr = makeTypeAttr(c_type, c);
            rval.get.primary.type.attr.isDefinition = old_def;
        }
    }

    auto handleTypeWithDecl(ref Nullable!TypeResults rval) {
        auto c_type_decl = c_type.declaration;
        if (c_type_decl.isValid) {
            auto type = c_type_decl.type;
            rval = passType(c_type_decl, type, container, indent);
        }
    }

    auto handleArray(ref Nullable!TypeResults rval) {
        // must check for array:nes before Typedef because of the case when it
        // is an array of typedef's
        if (c_type.isArray) {
            rval = typeToArray(c, c_type, container, indent);
        }
    }

    auto fallback(ref Nullable!TypeResults rval) {
        rval = passType(c, c_type, container, indent);
    }

    auto ensureUSR(ref Nullable!TypeResults rval) {
        if (!rval.isNull && rval.get.primary.type.kind.usr.length == 0) {
            rval.get.primary.type.kind.usr = makeFallbackUSR(c, this_indent);
        }
    }

    Nullable!TypeResults rval;
    foreach (idx, f; [
        &handlePointer, &handleArray, &handleTypedef, &handleTypeWithDecl,
        &fallback
    ]) {
        debug {
            import std.conv : to;

            logger.trace(idx.to!string(), this_indent);
        }

        f(rval);
        if (!rval.isNull) {
            break;
        }
    }

    ensureUSR(rval);

    return rval;
}

private Nullable!TypeResults retrieveTypeAlias(const Cursor c,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind.among(CXCursorKind.CXCursor_TypeAliasDecl,
            CXCursorKind.CXCursor_TypeAliasTemplateDecl));
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    const uint indent = this_indent + 1;

    Nullable!TypeResults rval;

    foreach (child; c.children) {
        if (!child.kind.among(CXCursorKind.CXCursor_TypeRef, CXCursorKind.CXCursor_TypeAliasDecl)) {
            continue;
        }

        auto tref = pass4(child, container, indent);

        auto type = c.type;
        // duplicated code from retrieveTypeDef -> handleTyperef
        // TODO consider if this can be harmonized with Typedef.
        // Maybe this is a special case?
        // Shouldn't be per se locked to a TypeDefDecl but rather the concept
        // of a type that is an alias for another.
        tref.get.primary.type.kind.info.match!((TypeKind.TypeRefInfo t) {
            rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                t.canonicalRef, container, indent);
        }, (_) {
            rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                tref.get.primary.type.kind.usr, container, indent);
        });
        rval.get.extra = [tref.get.primary] ~ tref.get.extra;
    }

    if (rval.isNull && c.kind == CXCursorKind.CXCursor_TypeAliasDecl) {
        auto type = c.type;
        rval = typeToSimple(c, type, indent);
    }

    return rval;
}

private Nullable!TypeResults retrieveTypeDef(const Cursor c,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind == CXCursorKind.CXCursor_TypedefDecl);
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    import std.range : takeOne;

    const uint indent = this_indent + 1;

    void handleTyperef(ref Nullable!TypeResults rval) {
        import std.algorithm : filter;

        if (isFuncProtoTypedef(c)) {
            // this case is handled by handleTyperefFuncProto
            return;
        }

        // any TypeRef children and thus need to traverse the tree?
        foreach (child; c.children.filterByTypeRef.filter!(
                a => a.kind == CXCursorKind.CXCursor_TypeRef).takeOne) {
            auto tref = pass4(child, container, indent);

            auto type = c.type;
            tref.get.primary.type.kind.info.match!((TypeKind.TypeRefInfo t) {
                rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                    t.canonicalRef, container, indent);
            }, (_) {
                rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                    tref.get.primary.type.kind.usr, container, indent);
            });
            rval.get.extra = [tref.get.primary] ~ tref.get.extra;
        }
    }

    void handleDecl(ref Nullable!TypeResults rval) {
        auto child_ = c.children.takeOne;
        if (child_.length == 0 || !child_[0].kind.canConvertNodeDeclToType) {
            return;
        }

        auto c_child = child_[0];
        auto tref = retrieveType(c_child, container, indent);

        auto type = c.type;
        tref.get.primary.type.kind.info.match!((TypeKind.TypeRefInfo t) {
            rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                t.canonicalRef, container, indent);
        }, (_) {
            rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                tref.get.primary.type.kind.usr, container, indent);
        });

        rval.get.extra = [tref.get.primary] ~ tref.get.extra;
    }

    auto handleTypeRefToTypeDeclFuncProto(ref Nullable!TypeResults rval) {
        static bool isFuncProto(const Cursor c) {
            //TODO consider merging or improving isFuncProtoTypedef with this
            if (!isFuncProtoTypedef(c)) {
                return false;
            }

            if (c.children.length == 0) {
                return false;
            }

            auto child_t = c.children[0].type;
            if (!child_t.isFunctionType || child_t.isPointer) {
                return false;
            }

            return true;
        }

        if (!isFuncProto(c)) {
            return;
        }

        auto child = c.children[0];
        auto ref_child = child.referenced;
        if (ref_child.kind != CXCursorKind.CXCursor_TypedefDecl) {
            return;
        }

        auto tref = retrieveType(ref_child, container, indent);

        // TODO consolidate code. Copied from handleDecl
        auto type = c.type;
        tref.get.primary.type.kind.info.match!((TypeKind.TypeRefInfo t) {
            rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                t.canonicalRef, container, indent);
        }, (_) {
            rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                tref.get.primary.type.kind.usr, container, indent);
        });
        rval.get.extra = [tref.get.primary] ~ tref.get.extra;
    }

    auto handleFuncProto(ref Nullable!TypeResults rval) {
        if (!isFuncProtoTypedef(c)) {
            return;
        }

        auto type = c.type;
        auto func = typeToFuncProto!(TypeKind.FuncSignatureInfo)(c, type, container, indent);

        rval = typeToTypedef(c, type, func.get.primary.type.kind.usr,
                func.get.primary.type.kind.usr, container, indent);
        rval.get.extra = [func.get.primary] ~ func.get.extra;
    }

    auto underlying(ref Nullable!TypeResults rval) {
        // TODO this function is convoluted and complex. Consider how it can be rewritten.

        auto underlying = c.typedefUnderlyingType;
        auto underlying_decl_c = underlying.declaration;

        Nullable!TypeResults tref;
        // assuming that there are typedef nodes that have no declaration.
        if (underlying_decl_c.isValid) {
            tref = passType(underlying_decl_c, underlying, container, indent);
        } else {
            tref = passType(c, underlying, container, indent);
            // ensure it is unique
            tref.get.primary.type.kind.usr = makeFallbackUSR(c, indent);
        }

        USRType canonical_usr = tref.get.primary.type.kind.info.match!(
                (TypeKind.TypeRefInfo t) => t.canonicalRef, (_) => tref.get.primary.type.kind.usr);

        auto type = c.type;
        rval = typeToTypedef(c, type, tref.get.primary.type.kind.usr,
                canonical_usr, container, indent);
        rval.get.extra = [tref.get.primary] ~ tref.get.extra;
    }

    void handleArray(ref Nullable!TypeResults rval) {
        // a constant array typedef has an integerLiteral as child.
        // handleDecl is built on the assumption that the first child of a
        // declaration that is a typedef is the "reference". As can be seen it
        // is wrong in the case for a constant array.
        auto underlying_t = c.typedefUnderlyingType;

        if (underlying_t.isArray) {
            underlying(rval);
        }
    }

    // TODO investigate if this can be removed, aka always covered by underlying.
    auto fallback(ref Nullable!TypeResults rval) {
        // fallback, unable to represent as a typedef ref'ing a type
        auto type = c.type;
        rval = passType(c, type, container, indent);
    }

    typeof(return) rval;
    foreach (idx, f; [
        &handleTypeRefToTypeDeclFuncProto, &handleArray, &handleTyperef,
        &handleFuncProto, &handleDecl, &underlying, &fallback
    ]) {
        debug {
            import std.conv : to;

            logger.trace(idx.to!string(), this_indent);
        }
        f(rval);
        if (!rval.isNull) {
            break;
        }
    }

    return rval;
}

/** Retrieve the type representation of a FuncDecl or CXXMethod.
 *
 * case a. A typedef of a function signature.
 * When it is instantiated it results in a FunctionDecl with a TypeRef.
 * Note in the example that the child node is a TypeRef.
 * Using the resultType to distinguish between a typedef function signature and
 * a function returning a function ptr.
 *
 * Example:
 * FunctionDecl "tiger" [Keyword "extern", Identifier "func_type", Identifier "tiger"] c:@F@tiger
 *   TypeRef "func_type" [Identifier "func_type"]
 *
 * case b. A function with a return type which is a TypeRef to a TypedefDecl.
 * The first child node is a TypeRef.
 * This case should NOT be confused with case a.
 *
 * case c. A function declared "the normal way", void foo();
 *
 * solve case a.
 * Try resolving the type of the first child node.
 * If the canonical type is a function, good. Case a.
 * Otherwise case b and c.
 */
private Nullable!TypeResults retrieveFunc(const Cursor c,
        ref Container container, const uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind.among(CXCursorKind.CXCursor_FunctionDecl, CXCursorKind.CXCursor_CXXMethod));
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    import std.algorithm : filter;
    import std.range : chain, only;
    import cpptooling.data : FuncFmt;

    immutable indent = this_indent + 1;
    typeof(return) rval;

    // distinguish between a child node that is for the return value from those
    // cases when it is a function derived from a typedef:ed function signature.
    auto result_decl_usr = c.func.resultType.declaration.usr;

    foreach (child; c.children.filterByTypeRef.filter!((a) {
            auto tmp = a.referenced.usr;
            return tmp != result_decl_usr;
        })) {
        if (child.kind != CXCursorKind.CXCursor_TypeRef) {
            break;
        }
        auto retrieved_ref = retrieveType(child, container, indent);

        if (retrieved_ref.isNull) {
            continue;
        }

        retrieved_ref.get.primary.type.kind.info.match!((TypeKind.FuncInfo t) {
            // fast path
            rval = retrieved_ref;
        }, (TypeKind.TypeRefInfo t) {
            // check the canonical type
            foreach (k; chain(only(retrieved_ref.get.primary), retrieved_ref.get.extra)) {
                if (k.type.kind.usr != t.canonicalRef) {
                    continue;
                }

                k.type.kind.info.match!((TypeKind.FuncInfo t) {
                    rval = retrieved_ref;
                }, (TypeKind.FuncSignatureInfo t) {
                    // function declaration of a typedef'ed signature
                    rval = retrieved_ref;
                    rval.get.extra ~= rval.get.primary;

                    auto prim = k;
                    prim.type.kind.info = TypeKind.FuncInfo(FuncFmt(k.type.kind.splitTypeId(indent)),
                    t.return_, t.returnAttr, t.params);
                    prim.location = makeLocation(c);
                    prim.type.kind.usr = makeFallbackUSR(c, this_indent);
                    rval.get.primary = prim;
                }, (_) {});

            }
        }, (_) {});
    }

    if (rval.isNull) {
        auto type = c.type;
        rval = passType(c, type, container, indent);
    }

    return rval;
}

/** Only able to uniquely represent the class template.
 *
 * TODO Unable to instansiate.
 */
private Nullable!TypeResults retrieveClassTemplate(const Cursor c,
        ref Container container, in uint indent)
in {
    import std.algorithm : among;

    logNode(c, indent);
    assert(c.kind.among(CXCursorKind.CXCursor_ClassTemplate,
            CXCursorKind.CXCursor_ClassTemplatePartialSpecialization));
}
do {
    TypeResults rval;

    auto type = c.type;
    rval.primary.type = makeTypeKindAttr(type, c);
    rval.primary.type.kind.info = TypeKind.SimpleInfo(SimpleFmt(TypeId(c.spelling)));
    rval.primary.type.kind.usr = c.usr;
    rval.primary.location = makeLocation(c);

    return typeof(return)(rval);
}

private Nullable!TypeResults retrieveClassBaseSpecifier(const Cursor c,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind == CXCursorKind.CXCursor_CXXBaseSpecifier);
}
do {
    auto indent = this_indent + 1;

    // when the cursor references a definition. easy
    bool tryReferenced(ref Nullable!TypeResults rval) {
        logger.trace("", this_indent);
        auto c_ref = c.referenced;

        if (c_ref.kind == CXCursorKind.CXCursor_NoDeclFound) {
            return false;
        }

        rval = retrieveType(c_ref, container, indent);

        return true;
    }

    // no definition exist. e.g in the cases of a template instantiation.
    bool reconstructFromCursor(ref Nullable!TypeResults rval_) {
        logger.trace("", this_indent);

        TypeResults rval;

        auto type = c.type;
        rval.primary.type = makeTypeKindAttr(type, c);

        rval.primary.type.kind.info = TypeKind.SimpleInfo(SimpleFmt(TypeId(c.spelling)));
        rval.primary.type.kind.usr = makeEnsuredUSR(c, indent);
        rval.primary.location = makeLocation(c);

        rval_ = Nullable!TypeResults(rval);

        return true;
    }

    Nullable!TypeResults rval;

    foreach (idx, f; [&tryReferenced, &reconstructFromCursor]) {
        if (f(rval)) {
            break;
        }
    }

    return rval;
}

/** Extract the type of a parameter cursor.
 *
 * TODO if nothing changes remove either retrieveParam or retrieveInstanceDecl,
 * code duplication.
 */
private Nullable!TypeResults retrieveParam(const Cursor c, ref Container container,
        in uint this_indent)
in {
    logNode(c, this_indent);
    // TODO add assert for the types allowed
}
out (result) {
    logTypeResult(result, this_indent);
}
do {
    return retrieveInstanceDecl(c, container, this_indent + 1);
}

/** Only able to uniquely represent the class template.
 *
 * TODO Unable to instansiate.
 */
private Nullable!TypeResults retrieveTemplateParam(const Cursor c,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    // TODO add assert for the types allowed
}
do {
    import std.range : takeOne;

    uint indent = this_indent + 1;
    Nullable!TypeResults rval;

    if (c.spelling.length == 0) {
        //TODO could probably be a random name, the location or something.
        // Example when it occurs:
        // template <typename/*here*/> class allocator;
        return rval;
    }

    auto type = c.type;
    rval = retrieveParam(c, container, indent);

    return rval;
}

private alias ExtractParamsResult = Tuple!(TypeResult, "result", string, "id",
        Flag!"isVariadic", "isVariadic");
private alias ExtractParamsResults = Tuple!(ExtractParamsResult[], "params",
        TypeResult[], "extra");

private ExtractParamsResults extractParams(const Cursor c, ref Type type,
        ref Container container, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.isFunctionType || type.isTypedef || type.kind == CXTypeKind.CXType_FunctionNoProto);
}
out (result) {
    foreach (p; result.params) {
        logger.trace(p.result.type.toStringDecl(p.id), this_indent);
    }

    foreach (e; result.extra) {
        logTypeResult(e, this_indent);
    }
}
do {
    const auto indent = this_indent + 1;

    void appendParams(const Cursor c, ref ExtractParamsResults rval) {
        import std.range : enumerate;

        foreach (idx, p; c.children.enumerate) {
            if (p.kind != CXCursorKind.CXCursor_ParmDecl) {
                logNode(p, this_indent);
                continue;
            }

            auto tka = retrieveType(p, container, indent);
            auto id = p.spelling;
            rval.params ~= ExtractParamsResult(tka.get.primary, id, No.isVariadic);
            rval.extra ~= tka.get.extra;
        }

        if (type.func.isVariadic) {
            import clang.SourceLocation;

            TypeResult result;

            auto info = TypeKind.SimpleInfo(SimpleFmt(TypeId("...")));
            result.type.kind.info = info;
            result.type.kind.usr = "..." ~ c.location.toString();
            result.location = makeLocation(c);

            // TODO remove this ugly hack
            // space as id to indicate it is empty
            rval.params ~= ExtractParamsResult(result, " ", Yes.isVariadic);
        }
    }

    ExtractParamsResults rval;

    if (c.kind == CXCursorKind.CXCursor_TypeRef) {
        auto cref = c.referenced;
        appendParams(cref, rval);
    } else {
        appendParams(c, rval);
    }

    return rval;
}

/// Join an array slice of PTuples to a parameter string of "type" "id"
private string joinParamId(ExtractParamsResult[] r) {
    import std.algorithm : joiner, map, filter;
    import std.conv : text;
    import std.range : enumerate;

    static string getTypeId(ref ExtractParamsResult p, ulong uid) {
        if (p.id.length == 0) {
            //TODO decide if to autogenerate for unnamed parameters here or later
            //return p.tka.toStringDecl("x" ~ text(uid));
            return p.result.type.toStringDecl("");
        } else {
            return p.result.type.toStringDecl(p.id);
        }
    }

    // using cache to avoid calling getName twice.
    return r.enumerate
        .map!(a => getTypeId(a.value, a.index))
        .filter!(a => a.length > 0)
        .joiner(", ").text();

}

private Nullable!string translateCursorType(CXTypeKind kind)
in {
    import std.conv : to;

    logger.trace(to!string(kind));
}
out (result) {
    logger.trace(!result.isNull, result);
}
do {
    Nullable!string r;

    // a good file to see what the types are:
    // https://github.com/llvm-mirror/clang/blob/master/include/clang/AST/BuiltinTypes.def

    switch (kind) with (CXTypeKind) {
    case CXType_Invalid:
        break;
    case CXType_Unexposed:
        break;
    case CXType_Void:
        r = "void";
        break;
    case CXType_Bool:
        r = "bool";
        break;
    case CXType_Char_U:
        r = "unsigned char";
        break;
    case CXType_UChar:
        r = "unsigned char";
        break;
    case CXType_Char16:
        break;
    case CXType_Char32:
        break;
    case CXType_UShort:
        r = "unsigned short";
        break;
    case CXType_UInt:
        r = "unsigned int";
        break;
    case CXType_ULong:
        r = "unsigned long";
        break;
    case CXType_ULongLong:
        r = "unsigned long long";
        break;
    case CXType_UInt128:
        r = "__uint128_t";
        break;
    case CXType_Char_S:
        r = "char";
        break;
    case CXType_SChar:
        r = "char";
        break;
    case CXType_WChar:
        r = "wchar_t";
        break;
    case CXType_Short:
        r = "short";
        break;
    case CXType_Int:
        r = "int";
        break;
    case CXType_Long:
        r = "long";
        break;
    case CXType_LongLong:
        r = "long long";
        break;
    case CXType_Int128:
        r = "__int128_t";
        break;
    case CXType_Float:
        r = "float";
        break;
    case CXType_Double:
        r = "double";
        break;
    case CXType_LongDouble:
        r = "long double";
        break;
    case CXType_NullPtr:
        r = "nullptr";
        break;
    case CXType_Overload:
        // The type of an unresolved overload set.  A placeholder type.
        // Expressions with this type have one of the following basic
        // forms, with parentheses generally permitted:
        //   foo          # possibly qualified, not if an implicit access
        //   foo          # possibly qualified, not if an implicit access
        //   &foo         # possibly qualified, not if an implicit access
        //   x->foo       # only if might be a static member function
        //   &x->foo      # only if might be a static member function
        //   &Class::foo  # when a pointer-to-member; sub-expr also has this type
        // OverloadExpr::find can be used to analyze the expression.
        //
        // Overload should be the first placeholder type, or else change
        // BuiltinType::isNonOverloadPlaceholderType()
        break;
    case CXType_Dependent:
        // This represents the type of an expression whose type is
        // totally unknown, e.g. 'T::foo'.  It is permitted for this to
        // appear in situations where the structure of the type is
        // theoretically deducible.
        break;

    case CXType_ObjCId:
    case CXType_ObjCClass:
    case CXType_ObjCSel:
        break;

    case CXType_Float128:
        r = "__float128";
        break;

    case CXType_Half:
        // half in OpenCL, otherwise __fp16
    case CXType_Float16:
        r = "__fp16";
        break;

    case CXType_ShortAccum:
        r = "short _Accum";
        break;
    case CXType_Accum:
        r = "_Accum";
        break;
    case CXType_LongAccum:
        r = "long _Accum";
        break;
    case CXType_UShortAccum:
        r = "unsigned short _Accum";
        break;
    case CXType_UAccum:
        r = "unsigned _Accum";
        break;
    case CXType_ULongAccum:
        r = "unsigned long _Accum";
        break;

    case CXType_Complex:
    case CXType_Pointer:
    case CXType_BlockPointer:
    case CXType_LValueReference:
    case CXType_RValueReference:
    case CXType_Record:
    case CXType_Enum:
    case CXType_Typedef:
    case CXType_ObjCInterface:
    case CXType_ObjCObjectPointer:
    case CXType_FunctionNoProto:
    case CXType_FunctionProto:
    case CXType_ConstantArray:
    case CXType_Vector:
    case CXType_IncompleteArray:
    case CXType_VariableArray:
    case CXType_DependentSizedArray:
    case CXType_MemberPointer:
        break;

    case CXType_Auto:
        r = "auto";
        break;

        /**
     * \brief Represents a type that was referred to using an elaborated type keyword.
     *
     * E.g., struct S, or via a qualified name, e.g., N::M::type, or both.
     */
    case CXType_Elaborated:
        break;
    default:
    }

    return r;
}
