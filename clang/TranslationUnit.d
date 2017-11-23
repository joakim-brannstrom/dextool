/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Oct 1, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */

module clang.TranslationUnit;

import std.string;

import clang.c.Index;

import clang.Cursor;
import clang.Diagnostic;
import clang.File;
import clang.Index;
import clang.SourceLocation;
import clang.SourceRange;
import clang.Visitor;

/** A single translation unit, which resides in an index.
 */
struct TranslationUnit {
    import std.typecons : Nullable;
    import clang.Util;

    static private struct ContainTU {
        mixin CX!("TranslationUnit");

        ~this() @safe {
            dispose();
        }
    }

    ContainTU cx;
    alias cx this;

    // the translation unit is destroyed when the dtor is ran.
    @disable this(this);

    /**
     * Trusted: on the assumption that clang_parseTranslationUnit is
     * implemented by the LLVM team.
     */
    static TranslationUnit parse(ref Index index, string sourceFilename, string[] commandLineArgs,
            CXUnsavedFile[] unsavedFiles = null,
            uint options = CXTranslationUnit_Flags.detailedPreprocessingRecord) @trusted {

        // dfmt off
        // Trusted: on the assumption that the LLVM team are competent. That
        // any problems that exist would have been found by now.
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

        return TranslationUnit(p);
    }

    /** Convenient function to create a TranslationUnit from source code via a
     * parameter.
     *
     * Common use cases is unit testing.
     *
     * Trusted: on the assumption that
     * clang.TranslationUnit.TranslationUnit.~this is correctly implemented.
     */
    static TranslationUnit parseString(ref Index index, string source, string[] commandLineArgs,
            CXUnsavedFile[] unsavedFiles = null,
            uint options = CXTranslationUnit_Flags.detailedPreprocessingRecord) @trusted {
        import std.string : toStringz;

        string path = randomSourceFileName;
        CXUnsavedFile file;
        if (source.length == 0) {
            file = CXUnsavedFile(path.toStringz, null, source.length);
        } else {
            file = CXUnsavedFile(path.toStringz, &source[0], source.length);
        }

        auto in_memory_files = unsavedFiles ~ [file];

        auto translationUnit = TranslationUnit.parse(index, path,
                commandLineArgs, in_memory_files, options);

        return translationUnit;
    }

    private static string randomSourceFileName() @safe {
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

        auto s = "random_source_filename.h";
        return buildPath(virtualPath, s);
    }

    package this(CXTranslationUnit cx) {
        this.cx = ContainTU(cx);
    }

    bool isValid() @trusted {
        return cx.isValid;
    }

    /**
     * Trusted: on the assumption that accessing the payload of the refcounted
     * TranslationUnit is @safe.
     */
    @property DiagnosticVisitor diagnostics() @trusted {
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

    File file() @safe {
        return file(spelling);
    }

    @property string spelling() @trusted {
        return toD(clang_getTranslationUnitSpelling(cx));
    }

    /**
     * Trusted: on the assumption that the LLVM team is superb programmers.
     */
    @property Cursor cursor() @trusted {
        auto r = clang_getTranslationUnitCursor(cx);
        return Cursor(r);
    }

    SourceLocation location(uint offset) @trusted {
        CXFile file = clang_getFile(cx, spelling.toStringz);
        return SourceLocation(clang_getLocationForOffset(cx, file, offset));
    }

    SourceLocation location(string path, uint offset) @trusted {
        CXFile file = clang_getFile(cx, path.toStringz);
        return SourceLocation(clang_getLocationForOffset(cx, file, offset));
    }

    SourceRange extent(uint startOffset, uint endOffset) {
        CXFile file = clang_getFile(cx, spelling.toStringz);
        auto start = clang_getLocationForOffset(cx, file, startOffset);
        auto end = clang_getLocationForOffset(cx, file, endOffset);
        return SourceRange(clang_getRange(start, end));
    }

    package SourceLocation[] includeLocationsImpl(Range)(Range cursors) @trusted {
        // `cursors` range should at least contain all global
        // preprocessor cursors, although it can contain more.

        bool[string] stacked;
        bool[string] included;
        SourceLocation[] locationStack;
        SourceLocation[] locations = [location("", 0), location(file.name, 0)];

        foreach (idx, cursor; cursors) {
            if (cursor.kind == CXCursorKind.inclusionDirective) {
                auto path = cursor.location.spelling.file.name;
                auto ptr = path in stacked;

                if (ptr !is null && *ptr) {
                    while (locationStack[$ - 1].path != path) {
                        stacked[locationStack[$ - 1].path] = false;
                        locations ~= locationStack[$ - 1];
                        locationStack = locationStack[0 .. $ - 1];
                    }

                    stacked[path] = false;
                    locations ~= locationStack[$ - 1];
                    locationStack = locationStack[0 .. $ - 1];
                }

                if ((cursor.include.file.name in included) is null) {
                    locationStack ~= cursor.extent.end;
                    stacked[path] = true;
                    locations ~= location(cursor.include.file.name, 0);
                    included[cursor.include.file.name] = true;
                }
            }
        }

        while (locationStack.length != 0) {
            locations ~= locationStack[$ - 1];
            locationStack = locationStack[0 .. $ - 1];
        }

        return locations;
    }

    SourceLocation[] includeLocations() {
        return includeLocationsImpl(cursor.all);
    }

    package ulong delegate(SourceLocation) relativeLocationAccessorImpl(Range)(Range cursors) {
        // `cursors` range should at least contain all global
        // preprocessor cursors, although it can contain more.

        SourceLocation[] locations = includeLocationsImpl(cursors);

        struct Entry {
            uint index;
            SourceLocation location;

            int opCmp(ref const Entry s) const {
                return location.offset < s.location.offset ? -1 : 1;
            }

            int opCmp(ref const SourceLocation s) const {
                return location.offset < s.offset + 1 ? -1 : 1;
            }
        }

        Entry[][string] map;

        foreach (uint index, location; locations)
            map[location.path] ~= Entry(index, location);

        uint findIndex(SourceLocation a) {
            auto entries = map[a.path];

            import std.range;

            auto lower = assumeSorted(entries).lowerBound(a);

            return lower.empty ? 0 : lower.back.index;
        }

        ulong accessor(SourceLocation location) {
            return ((cast(ulong) findIndex(location)) << 32) | (cast(ulong) location.offset);
        }

        return &accessor;
    }

    size_t delegate(SourceLocation) relativeLocationAccessor() {
        return relativeLocationAccessorImpl(cursor.all);
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

    this(CXTranslationUnit translatoinUnit) @safe {
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
