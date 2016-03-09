// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module test.tokenizer.main;

import std.conv;
import std.stdio;
import std.string;
import logger = std.experimental.logger;

import deimos.clang.index;

import clang.Util;

auto _getTokenKindSpelling(CXTokenKind kind) {
    with (CXTokenKind) switch (kind) {
    case CXToken_Punctuation:
        return "Punctuation";
    case CXToken_Keyword:
        return "Keyword";
    case CXToken_Identifier:
        return "Identifier";
    case CXToken_Literal:
        return "Literal";
    case CXToken_Comment:
        return "Comment";
    default:
        return "Unknown";
    }
}

void show_all_tokens(ref CXTranslationUnit tu, CXToken* tokens, uint numTokens) {
    writeln("=== show tokens ===");
    writef("NumTokens: %d\n", numTokens);
    for (auto i = 0U; i < numTokens; i++) {
        CXToken* token = &tokens[i];
        CXTokenKind kind = clang_getTokenKind(*token);
        CXString spell = clang_getTokenSpelling(tu, *token);
        CXSourceLocation loc = clang_getTokenLocation(tu, *token);

        CXFile file;
        uint line, column, offset;
        clang_getFileLocation(loc, &file, &line, &column, &offset);
        CXString fileName = clang_getFileName(file);

        writef("Token: %d\n", i);
        writef(" Text: %s\n", toD(spell));
        writef(" Kind: %s\n", _getTokenKindSpelling(kind));
        writef(" Location: %s:%d:%d:%d\n", toD(fileName), line, column, offset);
        writef("\n");

        clang_disposeString(fileName);
    }
}

auto get_filesize(in string fileName) {
    import std.file;

    return getSize(fileName);
}

CXSourceRange get_filerange(ref CXTranslationUnit tu, in string filename) {
    CXFile file = clang_getFile(tu, filename.toStringz);
    uint fileSize = cast(uint) get_filesize(filename);

    // get top/last location of the file
    CXSourceLocation topLoc = clang_getLocationForOffset(tu, file, 0);
    CXSourceLocation lastLoc = clang_getLocationForOffset(tu, file, fileSize);
    if (clang_equalLocations(topLoc, clang_getNullLocation())
            || clang_equalLocations(lastLoc, clang_getNullLocation())) {
        writef("cannot retrieve location\n");
        throw new Exception("location");
    }

    // make a range from locations
    CXSourceRange range = clang_getRange(topLoc, lastLoc);
    if (clang_Range_isNull(range)) {
        writef("cannot retrieve range\n");
        throw new Exception("range");
    }

    return range;
}

void show_clang_version() {
    CXString version_ = clang_getClangVersion();
    writef("%s\n", toD(version_));
}

int tokenize(string filename) {
    // create index w/ excludeDeclsFromPCH = 1, displayDiagnostics=1.
    CXIndex index = clang_createIndex(1, 1);

    // create Translation Unit
    CXTranslationUnit tu = clang_parseTranslationUnit(index,
            filename.toStringz, null, 0, null, 0, 0);
    if (tu == null) {
        writef("Cannot parse translation unit\n");
        return 1;
    }

    // get CXSouceRange of the file
    CXSourceRange range = get_filerange(tu, filename);

    // tokenize in the range
    CXToken* tokens;
    uint numTokens;
    clang_tokenize(tu, range, &tokens, &numTokens);

    // show tokens
    show_all_tokens(tu, tokens, numTokens);

    clang_disposeTokens(tu, tokens, numTokens);
    clang_disposeTranslationUnit(tu);
    clang_disposeIndex(index);

    return 0;
}

/// Root visitor of AST.
struct ShowAst {
    import cpptooling.utility.clang : visitAst, logNode;
    import cpptooling.utility.stack : VisitNodeDepth;
    import cpptooling.analyzer.clang.type : logType;
    import clang.Cursor;
    import clang.Type;
    import deimos.clang.index;

    private VisitNodeDepth depth_;
    alias depth_ this;

    void visit(Cursor cursor) {
        visitAst!(typeof(this))(cursor, this);
    }

    void applyRoot(ref Cursor root) {
        logNode(root, depth);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        apply(c);

        return true;
    }

    void apply(ref Cursor c) {
        logNode(c, depth);
        incr();

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_CXXBaseSpecifier:
            printBacktrack!(a => a == CXCursorKind.CXCursor_Namespace)(c,
                    "cxxbase -> namespace", depth);
            break;

        case CXCursor_ClassDecl:
            printBacktrack!(a => a == CXCursorKind.CXCursor_Namespace)(c,
                    "class -> namespace", depth);
            break;

        default:
            printBacktrack(c, "default", depth);
            break;
        }

        if (c.isValid) {
            // can only print tokens for valid cursors
            //printTokens(c, depth);

            // analyze type information
            //apply(c.type);
            //
            // analyze what a reference cursor point at
            if (c.isReference) {
                logger.info("is referenced");
                auto r = c.referenced;
                apply(r);
                apply(r.type);
            }
        }

        decr();
    }

    void apply(Type t) {
        import std.algorithm : among;

        logType(t);

        with (CXTypeKind) {
            if (t.kind.among(CXType_Pointer, CXType_LValueReference, CXType_BlockPointer)) {
                logger.info("is pointer");
                apply(t.pointeeType);
            }
        }

        if (!t.isExposed) {
            logger.info("is not exposed");
            auto c = t.declaration;
            if (c.isValid) {
                apply(c);
            } else {
                c = t.cursor.canonical();
                t = t.canonicalType;
                if (c.isValid) {
                    logger.infof("canonical '%s'", c.spelling);
                    logNode(c, depth + 1);
                    logType(t);
                    t = c.type;
                    logType(t);
                }
            }
        }
    }

    static void printBacktrack(alias pred = a => true)(ref Cursor c, string id, int depth) {
        import std.range : repeat;

        auto curr = c;
        while (curr.isValid) {
            bool m = pred(curr.kind);
            logger.trace(repeat(' ', depth), "|", m ? "ok|" : "no|", id);
            logNode(curr, depth);

            curr = curr.semanticParent;
            ++depth;
        }
    }

    static void printTokens(ref Cursor c, int depth) {
        import std.conv : text;
        import std.range : repeat;

        import clang.Token;

        auto toks = c.tokens();

        foreach (ref t; toks) {
            auto loc = t.location();
            logger.tracef("|%s%s [kind: %s, line=%d, col=%d off=%d", repeat(' ',
                    depth), t.spelling, text(t.kind), loc.line, loc.column, loc.offset);
        }
    }
}

int show_ast(string filename, string[] flags) {
    import cpptooling.analyzer.clang.context;
    import cpptooling.utility.clang : visitAst, logNode;

    auto file_ctx = ClangContext(filename, flags);
    auto show = ShowAst();
    show.visit(file_ctx.cursor);

    return 0;
}

int main(string[] args) {
    if (args.length < 3) {
        writeln("devtool <category> filename");
        writeln("categories: tok, ast");
        return 1;
    }

    string[] flags;
    if (args.length > 3) {
        flags = args[3 .. $];
    }

    show_clang_version();

    switch (args[1]) {
    case "tok":
        return tokenize(args[2]);
    case "ast":
        return show_ast(args[2], flags);
    default:
        return 1;
    }
}
