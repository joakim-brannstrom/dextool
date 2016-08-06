// Written in ehe D programming language.
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
*/
module cpptooling.analyzer.clang.type;

import std.algorithm : among;
import std.conv : to;
import std.string : format;
import std.traits;
import std.typecons : Flag, Yes, No, Nullable, Tuple;
import logger = std.experimental.logger;

import deimos.clang.index : CXTypeKind;
import clang.Cursor : Cursor;
import clang.Type : Type;

public import cpptooling.analyzer.type;
import cpptooling.data.type : Location, LocationTag;

private long _nextSequence;

static this() {
    // Use a fixed number to minimize the difference between two generated
    // diagrams. For example makes it possible to diff the generated data.
    //
    // It is extremly important to minimize differences.
    // Diffs are used as the basis to evaluate changes.
    // No diff, no evaluation needed from an architectural point of view.
    // A change? Further inspection needed.
    _nextSequence = 42;
}

private string nextSequence() @safe {
    import std.conv : text;

    if (_nextSequence == long.max) {
        _nextSequence = 1;
    }

    _nextSequence += 1;

    return text(_nextSequence);
}

/// Find the first typeref node, if any.
private auto takeOneTypeRef(T)(auto ref T in_) {
    import std.range : takeOne;
    import std.algorithm : filter, among;

    return in_.filter!(a => a.kind >= CXCursorKind.CXCursor_TypeRef
            && a.kind <= CXCursorKind.CXCursor_LastRef);
}

/** Iteratively try to construct a USR that is reproducable from the cursor.
 *
 * Only use when c.usr may return the empty string.
 *
 * Fallback case, using location to make it unique.
 */
private USRType makeFallbackUSR(ref const(Cursor) c, in uint this_indent)
out (result) {
    import cpptooling.utility.logger;

    trace(cast(string) result, this_indent);
    assert(result.length > 0);
}
body {
    import std.array : appender;
    import std.conv : to;
    import clang.SourceLocation;

    // strategy 1, derive from lexical parent
    auto loc_ = backtrackLocation(c);

    // strategy 2, I give up.
    // Problem with this is that it isn't possible to reverse engineer.
    //TODO fix the magic number 100. Coming from an internal state of backtrackLocation. NOT GOOD
    // Checking if it is null_ should have been enough
    if (loc_.tag.kind == BacktrackLocation.Tag.Kind.null_) {
        loc_.backtracked = 1;
        loc_.tag = nextSequence;
    }

    auto app = appender!string();
    putBacktrackLocation(c, loc_, app);

    return USRType(app.data);
}

private USRType makeUSR(string s)
out (result) {
    assert(result.length > 0);
}
body {
    return USRType(s);
}

void logType(ref Type type, in uint indent = 0, string func = __FUNCTION__, uint line = __LINE__) {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.info;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent).array();
        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d%s %s|%s|%s|%s|%s [%s:%d]",
             indent,
             indent_,
             type.cursor.usr,
             type.kind,
             abilities(type),
             type.isValid ? "valid" : "invalid",
             type.typeKindSpelling,
             func,
             line);
    }
    // dfmt on
}

private void assertTypeResult(const ref TypeResults result) {
    import std.range : chain, only;

    foreach (const ref tka; chain(only(result.primary), result.extra)) {
        assert(tka.type.toStringDecl("x").length > 0);
        assert(tka.type.kind.usr.length > 0);
        if (!tka.type.attr.isPrimitive && tka.type.kind.loc.kind != LocationTag.Kind.noloc) {
            assert(tka.type.kind.loc.file.length > 0);
        }
    }
}

struct BacktrackLocation {
    static import clang.SourceLocation;
    import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;
    import cpptooling.data.type : Location;

    union TagType {
        typeof(null) null_;
        cpptooling.data.type.Location loc;
        string spelling;
    }

    alias Tag = TaggedAlgebraic!TagType;

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
private BacktrackLocation backtrackLocation(ref const(Cursor) c) @safe {
    import clang.SourceLocation : toString;
    import cpptooling.data.type : Location;

    BacktrackLocation rval;

    Cursor parent = c;
    for (rval.backtracked = 0; rval.tag.kind == BacktrackLocation.Tag.Kind.null_
            && rval.backtracked < 100; ++rval.backtracked) {
        auto loc = parent.location;
        auto spell = loc.spelling;
        if (spell.file is null) {
            // do nothing
        } else if (spell.file.name.length != 0) {
            rval.tag = Location(spell.file.name, spell.line, spell.column);
        } else if (parent.isTranslationUnit) {
            rval.tag = Location(spell.file.name, spell.line, spell.column);
            break;
        }

        parent = () @trusted{ return parent.lexicalParent; }();
    }

    return rval;
}

/// TODO consider if .offset should be used too. But may make it harder to
/// reverse engineer a location.
private void putBacktrackLocation(T)(ref const(Cursor) c, BacktrackLocation back_loc, ref T app) @safe {
    static import cpptooling.data.type;

    // using a suffix that do NOT exist in the clang USR standard.
    // TODO lookup the algorithm for clang USR to see if $ is valid.
    enum marker = '$';

    final switch (back_loc.tag.kind) with (BacktrackLocation.Tag) {
    case Kind.loc:
        auto loc = cast(cpptooling.data.type.Location) back_loc.tag;
        app.put(loc.toString);
        break;
    case Kind.spelling:
        app.put(to!string(back_loc.tag));
        break;
    case Kind.null_:
        break;
    }

    app.put(marker);
    app.put(back_loc.backtracked.to!string);
    if (c.isValid) {
        app.put(() @trusted{ return c.spelling; }());
    }
}

LocationTag makeLocation(ref const(Cursor) c) @safe
out (result) {
    import std.utf : validate;

    validate(result.file);
}
body {
    import std.array : appender;

    auto loc = c.location.spelling;
    auto rval = Location(loc.file.name, loc.line, loc.column);

    if (rval.file.length > 0) {
        return LocationTag(rval);
    }

    auto loc_ = backtrackLocation(c);

    if (loc_.tag.kind == BacktrackLocation.Tag.Kind.null_) {
        return LocationTag(null);
    }

    auto app = appender!string();
    putBacktrackLocation(c, loc_, app);

    rval = Location(app.data, loc.line, loc.column);

    return LocationTag(rval);
}

TypeAttr makeTypeAttr(ref Type type) {
    TypeAttr attr;

    attr.isConst = cast(Flag!"isConst") type.isConst;
    attr.isRef = cast(Flag!"isRef")(type.kind == CXTypeKind.CXType_LValueReference);
    attr.isPtr = cast(Flag!"isPtr")(type.kind == CXTypeKind.CXType_Pointer);
    attr.isArray = cast(Flag!"isArray") type.isArray;

    // this may not work perfectly but trying for now
    auto decl = type.declaration;
    if (decl.isValid) {
        attr.isDefinition = cast(Flag!"isDefinition") decl.isDefinition;
    }

    return attr;
}

TypeKindAttr makeTypeKindAttr(ref Type type) {
    TypeKindAttr tka;
    tka.attr = makeTypeAttr(type);

    return tka;
}

TypeKindAttr makeTypeKindAttr(ref Type type, ref TypeKind tk) {
    auto tka = makeTypeKindAttr(type);
    tka.kind = tk;

    return tka;
}

import deimos.clang.index : CXCursorKind;
import cpptooling.data.symbol.container : Container;
import cpptooling.data.symbol.types : USRType;
import cpptooling.utility.clang : logNode;

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
Nullable!TypeResults retrieveType(ref const(Cursor) c,
        ref const(Container) container, in uint indent = 0)
in {
    logNode(c, indent);

    // unable to derive anything useful from a typeref when based on nothing else.
    // __va_list is an examle (found in stdarg.h).
    if (indent == 0 && c.kind.among(CXCursorKind.CXCursor_TypeRef,
            CXCursorKind.CXCursor_CXXBaseSpecifier, CXCursorKind.CXCursor_TemplateRef,
            CXCursorKind.CXCursor_NamespaceRef,
            CXCursorKind.CXCursor_MemberRef, CXCursorKind.CXCursor_LabelRef)) {
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
body {
    import std.range;

    Nullable!TypeResults rval;

    // bail early
    if (c.kind.among(CXCursorKind.CXCursor_MacroDefinition)) {
        return rval;
    }

    foreach (pass; only(&pass1, &pass2, &pass3)) {
        auto r = pass(c, indent + 1);
        if (!r.isNull) {
            rval = TypeResults(TypeResult(r, r.kind.loc), null);
            return rval;
        }
    }

    rval = pass4(c, container, indent + 1);
    return rval;
}

/** Pass 1, implicit anonymous types for struct and union.
 */
private Nullable!TypeKindAttr pass1(ref const(Cursor) c, uint indent)
in {
    logNode(c, indent);
}
body {
    Nullable!TypeKindAttr rval;

    if (!c.isAnonymous) {
        return rval;
    }

    switch (c.kind) with (CXCursorKind) {
    case CXCursor_StructDecl:
        goto case;
    case CXCursor_UnionDecl:
        auto type = c.type;
        rval = makeTypeKindAttr(type);

        string spell = type.spelling;
        rval.kind.info = TypeKind.SimpleInfo(spell ~ " %s");
        rval.kind.usr = USRType(c.usr);
        rval.kind.loc = makeLocation(c);
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
private Nullable!TypeKindAttr pass2(ref const(Cursor) c, uint indent)
in {
    logNode(c, indent);
}
body {
    Nullable!TypeKindAttr rval;

    switch (c.kind) with (CXCursorKind) {
    case CXCursor_StructDecl:
        goto case;
    case CXCursor_UnionDecl:
        goto case;
    case CXCursor_EnumDecl:
        if (c.spelling.length == 0) {
            auto type = c.type;
            rval = makeTypeKindAttr(type);

            string spell = type.spelling;
            rval.kind.info = TypeKind.SimpleInfo(spell ~ " %s");
            rval.kind.usr = USRType(c.usr);
            rval.kind.loc = makeLocation(c);
        }
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
private Nullable!TypeKindAttr pass3(ref const(Cursor) c, uint indent)
in {
    logNode(c, indent);
}
body {
    Nullable!TypeKindAttr rval;

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
private Nullable!TypeResults pass4(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    auto indent = this_indent + 1;
    Nullable!TypeResults rval;

    switch (c.kind) with (CXCursorKind) {
    case CXCursor_TypedefDecl:
        rval = retrieveTypeDef(c, container, indent);
        break;

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

    case CXCursor_TypeRef:
    case CXCursor_CXXBaseSpecifier:
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

private Nullable!TypeResults retrieveUnexposed(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind == CXCursorKind.CXCursor_UnexposedDecl);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    import std.range : takeOne;

    auto indent = this_indent + 1;
    Nullable!TypeResults rval;

    foreach (child; c.children.takeOne) {
        switch (child.kind) with (CXCursorKind) {
        case CXCursor_CXXMethod:
        case CXCursor_FunctionDecl:
            rval = pass4(child, container, indent);
            if (!rval.isNull && rval.primary.type.kind.info.kind != TypeKind.Info.Kind.func) {
                // cases like typeof(x) y;
                // fix in the future
                rval.nullify;
            }
            break;

        default:
        }
    }

    return rval;
}

private Nullable!TypeResults passType(ref const(Cursor) c, ref Type type,
        ref const(Container) container, in uint this_indent)
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
body {
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
private TypeResults typeToTypeRef(ref const(Cursor) c, ref Type type,
        USRType type_ref, USRType canonical_ref, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    const uint indent = this_indent + 1;
    string spell = type.spelling;

    // ugly hack
    if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
        spell = spell[6 .. $];
    }

    TypeKind.TypeRefInfo info;
    info.fmt = spell ~ " %s";
    info.typeRef = type_ref;
    info.canonicalRef = canonical_ref;

    TypeResults rval;
    rval.primary.type.attr = makeTypeAttr(type);
    rval.primary.type.kind.info = info;

    // a typedef like __va_list has a null usr
    if (c.usr.length == 0) {
        rval.primary.type.kind.usr = makeFallbackUSR(c, indent);
    } else {
        rval.primary.type.kind.usr = c.usr;
    }

    rval.primary.type.kind.loc = makeLocation(c);

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
private TypeResults typeToFallBackTypeDef(ref const(Cursor) c, ref Type type, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    string spell = type.spelling;

    // ugly hack to remove const
    if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
        spell = spell[6 .. $];
    }

    auto rval = makeTypeKindAttr(type);

    auto info = TypeKind.SimpleInfo(spell ~ " %s");
    rval.kind.info = info;

    // a typedef like __va_list has a null usr
    if (c.usr.length == 0) {
        rval.kind.usr = makeFallbackUSR(c, this_indent + 1);
    } else {
        rval.kind.usr = c.usr;
    }

    rval.kind.loc = makeLocation(c);

    return TypeResults(TypeResult(rval, rval.kind.loc), null);
}

private TypeResults typeToSimple(ref const(Cursor) c, ref Type type, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    auto rval = makeTypeKindAttr(type);

    auto maybe_primitive = translateCursorType(type.kind);

    if (maybe_primitive.isNull) {
        string spell = type.spelling;
        rval.kind.info = TypeKind.SimpleInfo(spell ~ " %s");

        rval.kind.usr = c.usr;
        if (rval.kind.usr.length == 0) {
            rval.kind.usr = makeFallbackUSR(c, this_indent + 1);
        }
        rval.kind.loc = makeLocation(c);
    } else {
        string spell = maybe_primitive.get;
        rval.kind.info = TypeKind.SimpleInfo(spell ~ " %s");
        rval.attr.isPrimitive = Yes.isPrimitive;

        rval.kind.usr = makeUSR(maybe_primitive.get);
        rval.kind.loc = LocationTag(null);
    }

    return TypeResults(TypeResult(rval, rval.kind.loc), null);
}

/// A function proto signature?
/// Workaround by checking if the return type is valid.
private bool isFuncProtoTypedef(ref const(Cursor) c) {
    auto result_t = c.type.func.resultType;
    return result_t.isValid;
}

private TypeResults typeToTypedef(ref const(Cursor) c, ref Type type, USRType typeRef,
        USRType canonicalRef, ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.kind == CXTypeKind.CXType_Typedef);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    string spell = type.spelling;

    // ugly hack
    if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
        spell = spell[6 .. $];
    }

    TypeKind.TypeRefInfo info;
    info.fmt = spell ~ " %s";
    info.typeRef = typeRef;
    info.canonicalRef = canonicalRef;

    TypeResults rval;
    rval.primary.type.attr = makeTypeAttr(type);
    rval.primary.type.kind.info = info;

    // a typedef like __va_list has a null usr
    if (c.usr.length == 0) {
        rval.primary.type.kind.usr = makeFallbackUSR(c, this_indent + 1);
    } else {
        rval.primary.type.kind.usr = c.usr;
    }

    rval.primary.type.kind.loc = makeLocation(c);

    return rval;
}

/** Make a Record from a declaration or definition.
 */
private TypeResults typeToRecord(ref const(Cursor) c, ref Type type, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
    assert(type.kind == CXTypeKind.CXType_Record);
}
out (result) {
    logTypeResult(result, indent);
}
body {
    string spell = type.spelling;

    // ugly hack needed when canonicalType has been used to get the type of a
    // cursor
    if (type.isConst && spell.length > 6 && spell[0 .. 6] == "const ") {
        spell = spell[6 .. $];
    }

    TypeKind.RecordInfo info;
    info.fmt = spell ~ " %s";

    auto rval = makeTypeKindAttr(type);
    rval.kind.info = info;

    if (c.isDeclaration) {
        auto decl_c = type.declaration;
        rval.kind.usr = decl_c.usr;
        rval.kind.loc = makeLocation(decl_c);
    } else {
        // fallback
        rval.kind.usr = c.usr;
        rval.kind.loc = makeLocation(c);
    }

    if (rval.kind.usr.length == 0) {
        rval.kind.usr = makeFallbackUSR(c, indent + 1);
        rval.kind.loc = makeLocation(c);
    }

    return TypeResults(TypeResult(rval, rval.kind.loc), null);
}

/** Represent a pointer type hierarchy.
 *
 * TypeResults.primary.attr is the pointed at attribute.
 */
private TypeResults typeToPointer(ref const(Cursor) c, ref Type type,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference));
}
out (result) {
    logTypeResult(result, this_indent);
    with (TypeKind.Info.Kind) {
        // allow catching the logical error in debug build
        assert(!result.primary.type.kind.info.kind.among(ctor, dtor, record, simple, array));
    }
}
body {
    import std.array;
    import std.range : dropBack;
    import cpptooling.utility.logger;

    auto indent = this_indent + 1;

    auto getPointee() {
        auto pointee = type.pointeeType;
        auto c_pointee = pointee.declaration;

        debug {
            logNode(c_pointee, indent);
            logType(pointee, indent);
        }

        TypeResults rval;

        // find the underlying type information
        if (pointee.kind == CXTypeKind.CXType_Unexposed) {
            pointee = type.canonicalType;
            while (pointee.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference)) {
                pointee = pointee.pointeeType;
            }
            rval = passType(c, pointee, container, indent).get;

            if (rval.primary.type.kind.info.kind == TypeKind.Info.Kind.record
                    && c_pointee.kind.isUnexposedDeclWithUSR) {
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
            }
        } else if (c_pointee.kind == CXCursorKind.CXCursor_NoDeclFound) {
            // primitive types do not have a declaration cursor.
            // find the underlying primitive type.
            while (pointee.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference)) {
                pointee = pointee.pointeeType;
            }

            rval = passType(c, pointee, container, indent).get;
        } else {
            rval = retrieveType(c_pointee, container, indent).get;
        }

        return rval;
    }

    auto pointee = getPointee();

    auto attrs = retrievePointeeAttr(type, indent);

    TypeKind.PointerInfo info;
    info.pointee = pointee.primary.type.kind.usr;
    info.attrs = attrs.ptrs;

    switch (pointee.primary.type.kind.info.kind) with (TypeKind.Info) {
    case Kind.array:
        info.fmt = pointee.primary.type.kind.toStringDecl(TypeAttr.init, "(%s%s)");
        break;
    default:
        info.fmt = pointee.primary.type.kind.toStringDecl(TypeAttr.init, "%s%s");
    }

    TypeResults rval;
    rval.primary.type.kind.info = info;
    // somehow pointee.primary.attr is wrong, somehow. Don't undestand why.
    // TODO remove this hack
    rval.primary.type.attr = attrs.base;

    if (pointee.primary.type.attr.isPrimitive) {
        // represent a usr to a primary more intelligently
        rval.primary.type.kind.usr = rval.primary.type.kind.toStringDecl(TypeAttr.init, "");
        // TODO shouldnt be needed, it is a primitive....
        rval.primary.type.kind.loc = makeLocation(c);
    } else {
        rval.primary.type.kind.usr = c.usr;
        rval.primary.type.kind.loc = makeLocation(c);
        if (rval.primary.type.kind.usr.length == 0) {
            rval.primary.type.kind.usr = makeFallbackUSR(c, indent);
        }
    }

    rval.extra = [pointee.primary] ~ pointee.extra;

    return rval;
}

/** Represent a function pointer type.
 *
 * Return: correct formatting and attributes for a function pointer.
 */
private TypeResults typeToFuncPtr(ref const(Cursor) c, ref Type type,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference));
    assert(type.isFunctionPointerType);
}
out (result) {
    logTypeResult(result, this_indent);
    with (TypeKind.Info.Kind) {
        // allow catching the logical error in debug build
        assert(!result.primary.type.kind.info.kind.among(ctor, dtor, record, simple, array));
    }
}
body {
    auto indent = this_indent + 1;

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
    info.pointee = pointee.primary.type.kind.usr;
    info.attrs = attrs.ptrs;
    info.fmt = pointee.primary.type.kind.toStringDecl(TypeAttr.init, "(%s%s)");

    TypeResults rval;
    rval.primary.type.kind.info = info;
    rval.primary.type.kind.usr = c.usr;
    rval.primary.type.kind.loc = makeLocation(c);
    // somehow pointee.primary.attr is wrong, somehow. Don't undestand why.
    // TODO remove this hack
    rval.primary.type.attr = attrs.base;

    rval.extra = [pointee.primary] ~ pointee.extra;

    return rval;
}

private TypeResults typeToFuncProto(ref const(Cursor) c, ref Type type,
        ref const(Container) container, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
    assert(type.isFunctionType || type.isTypedef || type.kind == CXTypeKind.CXType_FunctionNoProto);
}
out (result) {
    logTypeResult(result, indent);
}
body {
    import std.array;
    import std.algorithm : map;
    import std.string : strip;

    // TODO redesign. This is brittle and ugly.
    // return by value instead of splitting two ways like this.
    TypeKindAttr retrieveReturn(ref TypeResults rval) {
        auto result_type = type.func.resultType;
        auto result_decl = result_type.declaration;
        debug {
            logNode(result_decl, indent);
            logType(result_type, indent);
        }

        if (result_decl.kind == CXCursorKind.CXCursor_NoDeclFound) {
            rval = passType(result_decl, result_type, container, indent + 1).get;
        } else {
            rval = retrieveType(result_decl, container, indent + 1).get;
        }

        return rval.primary.type;
    }

    TypeResults rval;
    TypeResults return_rval;

    auto return_t = retrieveReturn(return_rval);
    auto params = extractParams(c, type, container, indent);
    auto primary = makeTypeKindAttr(type);

    // a C++ member function must be queried for constness via a different API
    primary.attr.isConst = cast(Flag!"isConst") c.func.isConst;

    TypeKind.FuncInfo info;
    info.fmt = format("%s %s(%s)", return_t.toStringDecl.strip, "%s", params.joinParamId());
    info.return_ = return_t.kind.usr;
    info.returnAttr = return_t.attr;
    info.params = params.map!(a => FuncInfoParam(a.tka.kind.usr, a.tka.attr, a.id, a.isVariadic)).array();

    primary.kind.info = info;
    // in the case of __sighandler_t it is already used for the typedef
    primary.kind.usr = makeFallbackUSR(c, indent);
    primary.kind.loc = makeLocation(c);

    rval.primary.type = primary;
    rval.extra ~= params.map!(a => TypeResult(a.tka, a.tka.kind.loc)).array();
    rval.extra ~= return_rval.primary;
    rval.extra ~= return_rval.extra;

    return rval;
}

private TypeResults typeToCtor(ref const(Cursor) c, ref Type type,
        ref const(Container) container, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
    assert(c.kind == CXCursorKind.CXCursor_Constructor);
}
out (result) {
    logTypeResult(result, indent);
}
body {
    import std.algorithm : map;
    import std.array;

    TypeResults rval;
    auto params = extractParams(c, type, container, indent);
    auto primary = makeTypeKindAttr(type);

    TypeKind.CtorInfo info;
    info.fmt = format("%s(%s)", "%s", params.joinParamId());
    info.params = params.map!(a => FuncInfoParam(a.tka.kind.usr, a.tka.attr, a.id, a.isVariadic)).array();
    info.id = c.spelling;

    primary.kind.info = info;
    primary.kind.usr = c.usr;
    primary.kind.loc = makeLocation(c);

    rval.primary.type = primary;
    rval.extra ~= params.map!(a => TypeResult(a.tka, a.tka.kind.loc)).array();

    return rval;
}

private TypeResults typeToDtor(ref const(Cursor) c, ref Type type, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
    assert(c.kind == CXCursorKind.CXCursor_Destructor);
}
out (result) {
    logTypeResult(result, indent);
}
body {
    TypeResults rval;
    auto primary = makeTypeKindAttr(type);

    TypeKind.DtorInfo info;
    info.fmt = format("~%s()", "%s");
    info.id = c.spelling[1 .. $]; // remove the leading ~

    primary.kind.info = info;
    primary.kind.usr = c.usr;
    primary.kind.loc = makeLocation(c);

    rval.primary.type = primary;
    return rval;
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
body {
    auto indent = this_indent + 1;
    PointerTypeAttr rval;

    if (type.kind.among(CXTypeKind.CXType_Pointer, CXTypeKind.CXType_LValueReference)) {
        // recursive
        auto pointee = type.pointeeType;
        rval = retrievePointeeAttr(pointee, indent);
        // current appended so right most ptr is at position 0.
        rval.ptrs ~= makeTypeAttr(type);
    } else {
        // Base condition.
        rval.base = makeTypeAttr(type);
    }

    return rval;
}

private TypeResults typeToArray(ref const(Cursor) c, ref Type type,
        ref const(Container) container, in uint indent)
in {
    logNode(c, indent);
    logType(type, indent);
}
out (result) {
    logTypeResult(result, indent);
    assert(result.primary.type.kind.info.kind == TypeKind.Info.Kind.array);
}
body {
    import std.format : format;
    import cpptooling.data.type : LocationTag, Location;

    ArrayInfoIndex[] index_nr;

    // beware, used in primitive arrays
    auto index = type;

    while (index.kind.among(CXTypeKind.CXType_ConstantArray, CXTypeKind.CXType_IncompleteArray)) {
        auto arr = index.array;

        switch (index.kind) with (CXTypeKind) {
        case CXType_ConstantArray:
            index_nr ~= ArrayInfoIndex(arr.size);
            break;
        case CXType_IncompleteArray:
            index_nr ~= ArrayInfoIndex();
            break;
        default:
            break;
        }

        index = arr.elementType;
    }

    TypeResults element;
    USRType primary_usr;
    LocationTag primary_loc;

    auto index_decl = index.declaration;

    if (index_decl.kind == CXCursorKind.CXCursor_NoDeclFound) {
        // on purpuse not checking if it is null before using
        element = passType(c, index, container, indent + 1).get;

        primary_usr = element.primary.type.kind.toStringDecl(TypeAttr.init) ~ index_nr.toRepr;
        primary_loc = element.primary.type.kind.loc;
    } else {
        // on purpuse not checking if it is null before using
        element = retrieveType(index_decl, container, indent + 1).get;

        primary_usr = element.primary.type.kind.usr;
        primary_loc = element.primary.type.kind.loc;
    }

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

    TypeKind.ArrayInfo info;
    info.element = element.primary.type.kind.usr;
    info.elementAttr = element.primary.type.attr;
    info.indexes = index_nr;
    // TODO probably need to adjust elementType and format to allow ptr to
    // array etc. int * const x[10];
    info.fmt = element.primary.type.kind.toStringDecl(TypeAttr.init, "%s%s");

    TypeResults rval;
    rval.primary.type.kind.usr = primary_usr;
    rval.primary.type.kind.loc = primary_loc;
    rval.primary.type.kind.info = info;
    rval.primary.type.attr = makeTypeAttr(type);
    rval.extra ~= [element.primary] ~ element.extra;

    return rval;
}

/** Retrieve the type of an instance declaration.
 *
 * Questions to consider:
 *  - Is the type a typeref?
 *  - Is it a function pointer?
 *  - Is the type a primitive type?
 */
private Nullable!TypeResults retrieveInstanceDecl(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
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
body {
    import std.range : takeOne;

    const auto indent = this_indent + 1;
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
                    rval.extra ~= [child.primary] ~ child.extra;
                }
            }
            break;

        default:
        }
    }

    auto handleTypedef(ref Nullable!TypeResults rval) {
        foreach (child; c.children.takeOne) {
            switch (child.kind) with (CXCursorKind) {
            case CXCursor_TypeRef:
                rval = pass4(child, container, indent);
                break;
            default:
            }
        }

        if (!rval.isNull) {
            rval.primary.type.attr = makeTypeAttr(c_type);
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
        if (!rval.isNull && rval.primary.type.kind.usr.length == 0) {
            rval.primary.type.kind.usr = makeFallbackUSR(c, this_indent);
        }
    }

    Nullable!TypeResults rval;
    foreach (idx, f; [&handlePointer, &handleArray, &handleTypedef,
            &handleTypeWithDecl, &fallback]) {
        debug {
            import std.conv : to;
            import cpptooling.utility.logger : trace;

            trace(idx.to!string(), this_indent);
        }
        f(rval);
        if (!rval.isNull) {
            break;
        }
    }

    ensureUSR(rval);

    return rval;
}

private Nullable!TypeResults retrieveTypeAlias(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind == CXCursorKind.CXCursor_TypeAliasDecl);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    const uint indent = this_indent + 1;

    Nullable!TypeResults rval;

    foreach (child; c.children) {
        if (child.kind != CXCursorKind.CXCursor_TypeRef) {
            continue;
        }

        auto tref = pass4(child, container, indent);

        auto type = c.type;
        // duplicated code from retrieveTypeDef -> handleTyperef
        // TODO consider if this can be harmonized with Typedef.
        // Maybe this is a special case?
        // Shouldn't be per se locked to a TypeDefDecl but rather the concept
        // of a type that is an alias for another.
        if (tref.primary.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                    tref.primary.type.kind.info.canonicalRef, container, indent);
        } else {
            rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                    tref.primary.type.kind.usr, container, indent);
        }
        rval.extra = [tref.primary] ~ tref.extra;
    }

    return rval;
}

private Nullable!TypeResults retrieveTypeDef(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind == CXCursorKind.CXCursor_TypedefDecl);
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    import std.range : takeOne;

    const uint indent = this_indent + 1;

    auto handleTyperef(ref Nullable!TypeResults rval) {
        if (isFuncProtoTypedef(c)) {
            // this case is handled by handleTyperefFuncProto
            return;
        }

        // any TypeRef children and thus need to traverse the tree?
        foreach (child; c.children.takeOneTypeRef) {
            if (!child.kind.among(CXCursorKind.CXCursor_TypeRef)) {
                break;
            }

            auto tref = pass4(child, container, indent);

            auto type = c.type;
            if (tref.primary.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
                rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                        tref.primary.type.kind.info.canonicalRef, container, indent);
            } else {
                rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                        tref.primary.type.kind.usr, container, indent);
            }
            rval.extra = [tref.primary] ~ tref.extra;
        }
    }

    auto handleDecl(ref Nullable!TypeResults rval) {
        auto child_ = c.children.takeOne;
        if (child_.length == 0 || !child_[0].kind.canConvertNodeDeclToType) {
            return;
        }

        auto c_child = child_[0];
        auto tref = retrieveType(c_child, container, indent);

        auto type = c.type;
        if (tref.primary.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                    tref.primary.type.kind.info.canonicalRef, container, indent);
        } else {
            rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                    tref.primary.type.kind.usr, container, indent);
        }
        rval.extra = [tref.primary] ~ tref.extra;
    }

    auto handleTypeRefToTypeDeclFuncProto(ref Nullable!TypeResults rval) {
        static bool isFuncProto(ref const(Cursor) c) {
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
        if (tref.primary.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                    tref.primary.type.kind.info.canonicalRef, container, indent);
        } else {
            rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                    tref.primary.type.kind.usr, container, indent);
        }
        rval.extra = [tref.primary] ~ tref.extra;
    }

    auto handleFuncProto(ref Nullable!TypeResults rval) {
        if (!isFuncProtoTypedef(c)) {
            return;
        }

        auto type = c.type;
        auto func = typeToFuncProto(c, type, container, indent);

        // a USR for the function do not exist because the only sensible would
        // be the typedef... but it is used by the typedef _for this function_
        func.primary.type.kind.usr = makeFallbackUSR(c, indent);

        rval = typeToTypedef(c, type, func.primary.type.kind.usr,
                func.primary.type.kind.usr, container, indent);
        rval.extra = [func.primary] ~ func.extra;
    }

    auto underlying(ref Nullable!TypeResults rval) {
        auto underlying = c.typedefUnderlyingType;
        auto tref = passType(c, underlying, container, indent);

        auto type = c.type;
        rval = typeToTypedef(c, type, tref.primary.type.kind.usr,
                tref.primary.type.kind.usr, container, indent);
        rval.extra = [tref.primary] ~ tref.extra;
    }

    // TODO investigate if this can be removed, aka always covered by underlying.
    auto fallback(ref Nullable!TypeResults rval) {
        // fallback, unable to represent as a typedef ref'ing a type
        auto type = c.type;
        rval = passType(c, type, container, indent);
    }

    typeof(return) rval;
    foreach (idx, f; [&handleTypeRefToTypeDeclFuncProto, &handleTyperef,
            &handleFuncProto, &handleDecl, &underlying, &fallback]) {
        debug {
            import std.conv : to;
            import cpptooling.utility.logger : trace;

            trace(idx.to!string(), this_indent);
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
 * When it is instansiated it results in a FunctionDecl with a TypeRef.
 * Note in the example that the child node is a TypeRef.
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
private Nullable!TypeResults retrieveFunc(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    assert(c.kind.among(CXCursorKind.CXCursor_FunctionDecl, CXCursorKind.CXCursor_CXXMethod));
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    import std.range : chain, only, takeOne;

    const uint indent = this_indent + 1;
    typeof(return) rval;

    foreach (child; c.children.takeOneTypeRef) {
        if (child.kind != CXCursorKind.CXCursor_TypeRef) {
            break;
        }
        auto retrieved_ref = retrieveType(child, container, indent);

        if (!retrieved_ref.isNull
                && retrieved_ref.primary.type.kind.info.kind == TypeKind.Info.Kind.func) {
            // fast path
            rval = retrieved_ref;
        } else if (!retrieved_ref.isNull
                && retrieved_ref.primary.type.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            // check the canonical type
            foreach (k; chain(only(retrieved_ref.primary), retrieved_ref.extra)) {
                if (k.type.kind.usr == retrieved_ref.primary.type.kind.info.canonicalRef
                        && k.type.kind.info.kind == TypeKind.Info.Kind.func) {
                    rval = retrieved_ref;
                }
            }
        }
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
private TypeResults retrieveClassTemplate(ref const(Cursor) c,
        ref const(Container) container, in uint indent)
in {
    import std.algorithm : among;

    logNode(c, indent);
    assert(c.kind.among(CXCursorKind.CXCursor_ClassTemplate,
            CXCursorKind.CXCursor_ClassTemplatePartialSpecialization));
}
body {
    TypeResults rval;

    auto type = c.type;
    rval.primary.type = makeTypeKindAttr(type);
    rval.primary.type.kind = makeSimple2(c.spelling);
    rval.primary.type.kind.usr = c.usr;
    rval.primary.type.kind.loc = makeLocation(c);

    return rval;
}

/** Extract the type of a parameter cursor.
 *
 * TODO if nothing changes remove either retrieveParam or retrieveInstanceDecl,
 * code duplication.
 */
private Nullable!TypeResults retrieveParam(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    // TODO add assert for the types allowed
}
out (result) {
    logTypeResult(result, this_indent);
}
body {
    return retrieveInstanceDecl(c, container, this_indent + 1);
}

/** Only able to uniquely represent the class template.
 *
 * TODO Unable to instansiate.
 */
private Nullable!TypeResults retrieveTemplateParam(ref const(Cursor) c,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    // TODO add assert for the types allowed
}
body {
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

private alias ExtractParamsResult = Tuple!(TypeKindAttr, "tka", string, "id",
        Flag!"isVariadic", "isVariadic");

ExtractParamsResult[] extractParams(ref const(Cursor) c, ref Type type,
        ref const(Container) container, in uint this_indent)
in {
    logNode(c, this_indent);
    logType(type, this_indent);
    assert(type.isFunctionType || type.isTypedef || type.kind == CXTypeKind.CXType_FunctionNoProto);
}
out (result) {
    import cpptooling.utility.logger : trace;

    foreach (p; result) {
        trace(p.tka.toStringDecl(p.id), this_indent);
    }
}
body {
    auto indent = this_indent + 1;

    void appendParams(ref const(Cursor) c, ref ExtractParamsResult[] params) {
        import std.range : enumerate;

        foreach (idx, p; c.children.enumerate) {
            if (p.kind != CXCursorKind.CXCursor_ParmDecl) {
                logNode(p, this_indent);
                continue;
            }

            auto tka = retrieveType(p, container, indent);
            auto id = p.spelling;
            params ~= ExtractParamsResult(tka.primary.type, id, No.isVariadic);
        }

        if (type.func.isVariadic) {
            import clang.SourceLocation;

            TypeKindAttr tka;

            auto info = TypeKind.SimpleInfo("...%s");
            tka.kind.info = info;
            tka.kind.usr = "..." ~ c.location.toString();
            tka.kind.loc = makeLocation(c);

            // TODO remove this ugly hack
            // space as id to indicate it is empty
            params ~= ExtractParamsResult(tka, " ", Yes.isVariadic);
        }
    }

    ExtractParamsResult[] params;

    if (c.kind == CXCursorKind.CXCursor_TypeRef) {
        auto cref = c.referenced;
        appendParams(cref, params);
    } else {
        appendParams(c, params);
    }

    return params;
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
            return p.tka.toStringDecl("");
        } else {
            return p.tka.toStringDecl(p.id);
        }
    }

    // using cache to avoid calling getName twice.
    return r.enumerate.map!(a => getTypeId(a.value, a.index)).filter!(a => a.length > 0)
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
body {
    Nullable!string r;

    with (CXTypeKind) switch (kind) {
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
        r = "null";
        break;
    case CXType_Overload:
        break;
    case CXType_Dependent:
        break;

    case CXType_ObjCId:
    case CXType_ObjCClass:
    case CXType_ObjCSel:
        break;

    case CXType_Complex:
    case CXType_Pointer:
    case CXType_BlockPointer:
    case CXType_LValueReference:
    case CXType_RValueReference:
    case CXType_Record:
    case CXType_Enum:
    case CXType_Typedef:
    case CXType_FunctionNoProto:
    case CXType_FunctionProto:
    case CXType_Vector:
    case CXType_IncompleteArray:
    case CXType_VariableArray:
    case CXType_DependentSizedArray:
    case CXType_MemberPointer:
        break;

    default:
        logger.trace("Unhandled type kind ", to!string(kind));
    }

    return r;
}
