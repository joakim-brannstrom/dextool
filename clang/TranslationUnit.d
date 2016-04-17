/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Oct 1, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */

module clang.TranslationUnit;

import std.string;

import deimos.clang.index;

import clang.Cursor;
import clang.Diagnostic;
import clang.File;
import clang.Index;
import clang.Visitor;

struct TranslationUnit {
    import std.typecons : Nullable, RefCounted;
    import clang.Util;

    static private struct ContainTU {
        mixin CX!("TranslationUnit");

        ~this() {
            dispose();
        }
    }

    RefCounted!ContainTU cx;
    alias cx this;

    static TranslationUnit parse(Index index, string sourceFilename,
            string[] commandLineArgs, CXUnsavedFile[] unsavedFiles = null,
            uint options = CXTranslationUnit_Flags.CXTranslationUnit_DetailedPreprocessingRecord) {

        // dfmt off
        auto p = clang_parseTranslationUnit(
                                            index.cx,
                                            sourceFilename.toStringz,
                                            strToCArray(commandLineArgs),
                                            cast(int) commandLineArgs.length,
                                            toCArray!(CXUnsavedFile)(unsavedFiles),
                                            cast(uint) unsavedFiles.length,
                                            options
                                            );
        // dfmt on

        auto r = TranslationUnit(p);

        return r;
    }

    static TranslationUnit parseString(Index index, string source,
            string[] commandLineArgs, CXUnsavedFile[] unsavedFiles = null,
            uint options = CXTranslationUnit_Flags.CXTranslationUnit_DetailedPreprocessingRecord) {
        import std.string : toStringz;
        import std.traits : fullyQualifiedName;
        import std.path : buildPath;

        static string virtualPath() {
            version (Windows)
                enum root = `C:\`;

            else
                enum root = "/";

            import std.conv : text;
            import std.random;

            return buildPath(root, text(uniform(1, 10_000_000)));
        }

        auto s = fullyQualifiedName!(typeof(this)) ~ ".h";
        auto path = buildPath(virtualPath, s);

        // in-memory file
        auto file = CXUnsavedFile(path.toStringz, source.ptr, source.length);

        auto translationUnit = TranslationUnit.parse(index, path,
                commandLineArgs, [file] ~ unsavedFiles, options);

        return translationUnit;
    }

    package this(CXTranslationUnit cx) {
        this.cx = cx;
    }

    @property DiagnosticVisitor diagnostics() {
        return DiagnosticVisitor(cx);
    }

    @property DiagnosticSet diagnosticSet() {
        return DiagnosticSet(clang_getDiagnosticSetFromTU(cx));
    }

    @property size_t numDiagnostics() {
        return clang_getNumDiagnostics(cx);
    }

    @property DeclarationVisitor declarations() {
        auto c = Cursor(clang_getTranslationUnitCursor(cx));
        return DeclarationVisitor(c);
    }

    Nullable!File file(string filename) @trusted {
        Nullable!File r;

        auto f = clang_getFile(cx, filename.toStringz);
        if (f !is null) {
            r = File(f);
        }

        return r;
    }

    File file() {
        return file(spelling);
    }

    @property string spelling() {
        return toD(clang_getTranslationUnitSpelling(cx));
    }

    @property Cursor cursor() {
        auto r = clang_getTranslationUnitCursor(cx);
        return Cursor(r);
    }
}

string dumpAST(ref TranslationUnit tu, bool skipIncluded = false) {
    import std.array : appender;
    import clang.Cursor : dumpAST;

    auto result = appender!string();
    auto c = tu.cursor;

    if (skipIncluded) {
        File file = tu.file;
        dumpAST(c, result, 0, &file);
    } else {
        dumpAST(c, result, 0);
    }

    return result.data;
}

struct DiagnosticVisitor {
    private CXTranslationUnit translatoinUnit;

    this(CXTranslationUnit translatoinUnit) {
        this.translatoinUnit = translatoinUnit;
    }

    size_t length() {
        return clang_getNumDiagnostics(translatoinUnit);
    }

    int opApply(int delegate(ref Diagnostic) dg) {
        int result;

        foreach (i; 0 .. length) {
            auto diag = clang_getDiagnostic(translatoinUnit, cast(uint) i);
            auto dDiag = Diagnostic(diag);
            result = dg(dDiag);

            if (result)
                break;
        }

        return result;
    }
}
