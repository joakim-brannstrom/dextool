// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module devtool.tok_main;

import std.conv;
import std.stdio;
import std.string;
import std.typecons : Yes;
import logger = std.experimental.logger;

import deimos.clang.index;

import clang.Util;

void showClangVersion() {
    CXString version_ = clang_getClangVersion();
    writef("%s\n", toD(version_));
}

void showAllTokens(ref CXTranslationUnit tu, CXToken* tokens, uint numTokens) {
    static auto _getTokenKindSpelling(CXTokenKind kind) {
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

CXSourceRange get_filerange(ref CXTranslationUnit tu, in string filename) {
    auto getFileSize(in string fileName) {
        import std.file;

        return getSize(fileName);
    }

    CXFile file = clang_getFile(tu, filename.toStringz);
    uint fileSize = cast(uint) getFileSize(filename);

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
    showAllTokens(tu, tokens, numTokens);

    clang_disposeTokens(tu, tokens, numTokens);
    clang_disposeTranslationUnit(tu);
    clang_disposeIndex(index);

    return 0;
}

int dumpAst(string filename, string[] flags) {
    import cpptooling.analyzer.clang.context;
    import clang.TranslationUnit : dumpAST;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto tu = ctx.makeTranslationUnit(filename, flags);
    writeln(dumpAST(tu));

    return 0;
}

int dumpBody(string fname, string[] flags) {
    import std.typecons : scoped, NullableRef;
    import cpptooling.analyzer.clang.analyze_helper;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.context;
    import cpptooling.analyzer.clang.utility : hasParseErrors, logDiagnostic;
    import cpptooling.utility.clang : logNode, mixinNodeLog;
    import cpptooling.data.symbol.container : Container;

    final class BodyVisitor : Visitor {
        alias visit = Visitor.visit;
        mixin generateIndentIncrDecr;

        NullableRef!Container container;

        this(ref Container container) {
            this.container = &container;
        }

        override void visit(const(Declaration) v) {
            mixin(mixinNodeLog!());
            v.accept(this);
        }

        override void visit(const(Statement) v) {
            mixin(mixinNodeLog!());
            v.accept(this);
        }

        override void visit(const(Expression) v) {
            mixin(mixinNodeLog!());
            v.accept(this);
        }

        override void visit(const(CallExpr) v) {
            mixin(mixinNodeLog!());

            auto c_func = v.cursor.referenced;
            logger.tracef("ref:'%s' kind:%s", c_func.spelling, c_func.kind.to!string());

            if (c_func.kind == CXCursorKind.CXCursor_FunctionDecl) {
                auto result = analyzeFunctionDecl(c_func, container, indent);
                () @trusted{ logger.trace("result: ", result); }();
            } else if (c_func.kind == CXCursorKind.CXCursor_CXXMethod) {
                auto result = analyzeCXXMethod(c_func, container, indent);
                () @trusted{ logger.trace("result: ", result); }();
            } else {
                logger.trace("unknown callexpr: ", c_func.kind.to!string());
            }

            v.accept(this);
        }

        override void visit(const(DeclRefExpr) v) {
            mixin(mixinNodeLog!());

            auto c_ref = v.cursor.referenced;
            logger.trace("ref: ", c_ref.spelling, " kind:", c_ref.kind.to!string());

            v.accept(this);
        }
    }

    final class MainVisitor : Visitor {
        alias visit = Visitor.visit;
        mixin generateIndentIncrDecr;

        Container container;

        override void visit(const(TranslationUnit) v) {
            mixin(mixinNodeLog!());
            v.accept(this);
        }

        override void visit(const(ClassDecl) v) {
            mixin(mixinNodeLog!());
            v.accept(this);
        }

        override void visit(const(StructDecl) v) {
            mixin(mixinNodeLog!());
            v.accept(this);
        }

        override void visit(const(FunctionDecl) v) @trusted {
            mixin(mixinNodeLog!());

            auto visitor = scoped!(BodyVisitor)(container);
            visitor.indent = indent;
            v.accept(visitor);
        }

        override void visit(const(CXXMethod) v) @trusted {
            mixin(mixinNodeLog!());

            auto visitor = scoped!(BodyVisitor)(container);
            visitor.indent = indent;
            v.accept(visitor);
        }
    }

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto tu = ctx.makeTranslationUnit(fname, flags);

    if (tu.hasParseErrors) {
        logDiagnostic(tu);
    }

    auto visitor = new MainVisitor;
    auto ast = ClangAST!(typeof(visitor))(tu.cursor);
    ast.accept(visitor);

    return 0;
}

int main(string[] args) {
    import application.logger : confLogLevel, ConfigureLog;

    confLogLevel(ConfigureLog.debug_);

    if (args.length < 3) {
        writeln("devtool <category> filename");
        writeln("categories: tok, dumpast, dumpbody");
        return 1;
    }

    string[] flags;
    if (args.length > 3) {
        flags = args[3 .. $];
    }

    showClangVersion();

    switch (args[1]) {
    case "tok":
        return tokenize(args[2]);
    case "dumpast":
        return dumpAst(args[2], flags);
    case "dumpbody":
        return dumpBody(args[2], flags);
    default:
        return 1;
    }
}
