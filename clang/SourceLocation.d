/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg, Joakim Brännström (joakim.brannstrom dottli gmx.com)
 * Version: 1.1
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 * History:
 *  1.0 initial release. 2012-01-29 $(BR)
 *    Jacob Carlborg
 *
 *  1.1 additional features missing compared to cindex.py. 2015-03-07 $(BR)
 *    Joakim Brännström
 */
module clang.SourceLocation;

import std.typecons;

import deimos.clang.index;

import clang.File;
import clang.TranslationUnit;
import clang.Util;

string toString(SourceLocation value) {
    import std.string;
    import std.conv;

    if (value.isValid) {
        auto spell = value.spelling;
        return format("%s(%s) [file=%s('%s') line=%d column=%d offset=%d]",
            text(typeid(value)), text(value.cx), text(spell.file),
            text(spell.file.name), spell.line, spell.column, spell.offset);
    }

    return format("%s(%s)", text(typeid(value)), text(value.cx));
}

/// A SourceLocation represents a particular location within a source file.
struct SourceLocation {
    mixin CX;

    struct Location {
        File file;
        uint line;
        uint column;
        uint offset;
    }

    // ugly hack. Must fix to something that works for both File and string.
    struct Location2 {
        string file;
        uint line;
        uint column;
        uint offset;
    }

    /// Retrieve a NULL (invalid) source location.
    static SourceLocation empty() {
        auto r = clang_getNullLocation();
        return SourceLocation(r);
    }

    /** Retrieves the source location associated with a given file/line/column
     * in a particular translation unit.
     * TODO consider moving to TranslationUnit instead
     *
     * Params:
     *  tu = translation unit to derive location from.
     *  file = a file in tu.
     *  line = text line. Starting at 1.
     *  offset = offset into the line. Starting at 1.
     */
    static Nullable!SourceLocation fromPosition(ref TranslationUnit tu,
        ref File file, uint line, uint offset) {

        auto rval = Nullable!SourceLocation();
        auto r = SourceLocation(clang_getLocation(tu, file, line, offset));
        if (r.file !is null) {
            rval = SourceLocation(r);
        }

        return rval;
    }

    /** Retrieves the source location associated with a given character offset
     * in a particular translation unit.
     * TODO consider moving to TranslationUnit instead
     */
    static SourceLocation fromOffset(ref TranslationUnit tu, ref File file, uint offset) {
        auto r = clang_getLocationForOffset(tu, file, offset);
        return SourceLocation(r);
    }

    /// Get the file represented by this source location.
    /// TODO implement with a cache, this is inefficient.
    @property File file() @safe {
        return expansion.file;
    }

    /// Get the line represented by this source location.
    /// TODO implement with a cache, this is inefficient.
    @property uint line() @safe {
        return expansion.line;
    }

    /// Get the column represented by this source location.
    /// TODO implement with a cache, this is inefficient.
    @property uint column() @safe {
        return expansion.column;
    }

    /// Get the file offset represented by this source location.
    /// TODO implement with a cache, this is inefficient.
    @property uint offset() @safe {
        return expansion.offset;
    }

    /** Retrieve the file, line, column, and offset represented by
     * the given source location.
     *
     * If the location refers into a macro expansion, retrieves the
     * location of the macro expansion.
     *
     * Location within a source file that will be decomposed into its parts.
     *
     * file [out] if non-NULL, will be set to the file to which the given
     * source location points.
     *
     * line [out] if non-NULL, will be set to the line to which the given
     * source location points.
     *
     * column [out] if non-NULL, will be set to the column to which the given
     * source location points.
     *
     * offset [out] if non-NULL, will be set to the offset into the
     * buffer to which the given source location points.
     */
    @property Location expansion() @trusted {
        Location data;

        clang_getExpansionLocation(cx, &data.file.cx, &data.line, &data.column, &data.offset);

        return data;
    }

    /** Retrieve the file, line, column, and offset represented by
     * the given source location, as specified in a # line directive.
     *
     * Example: given the following source code in a file somefile.c
     * ---
     * #123 "dummy.c" 1
     *
     * static int func()
     * {
     *     return 0;
     * }
     * ---
     * the location information returned by this function would be
     * ---
     * File: dummy.c Line: 124 Column: 12
     * ---
     * whereas clang_getExpansionLocation would have returned
     * ---
     * File: somefile.c Line: 3 Column: 12
     * ---
     *
     *  filename [out] if non-NULL, will be set to the filename of the
     * source location. Note that filenames returned will be for "virtual" files,
     * which don't necessarily exist on the machine running clang - e.g. when
     * parsing preprocessed output obtained from a different environment. If
     * a non-NULL value is passed in, remember to dispose of the returned value
     * using \c clang_disposeString() once you've finished with it. For an invalid
     * source location, an empty string is returned.
     *
     *  line [out] if non-NULL, will be set to the line number of the
     * source location. For an invalid source location, zero is returned.
     *
     *  column [out] if non-NULL, will be set to the column number of the
     * source location. For an invalid source location, zero is returned.
     */
    auto presumed() @trusted {
        Location2 data;
        CXString cxstring;

        clang_getPresumedLocation(cx, &cxstring, &data.line, &data.column);
        data.file = toD(cxstring);

        return data;
    }

    /** Retrieve the file, line, column, and offset represented by
     * the given source location.
     *
     * If the location refers into a macro instantiation, return where the
     * location was originally spelled in the source file.
     *
     * The location within a source file that will be decomposed into its
     * parts.
     *
     * file [out] if non-NULL, will be set to the file to which the given
     * source location points.
     *
     * line [out] if non-NULL, will be set to the line to which the given
     * source location points.
     *
     * column [out] if non-NULL, will be set to the column to which the given
     * source location points.
     *
     * offset [out] if non-NULL, will be set to the offset into the
     * buffer to which the given source location points.
     */
    @property Location spelling() @trusted {
        Location data;

        clang_getSpellingLocation(cx, &data.file.cx, &data.line, &data.column, &data.offset);

        return data;
    }
}
