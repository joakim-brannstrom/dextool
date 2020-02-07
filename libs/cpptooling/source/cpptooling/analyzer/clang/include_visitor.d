/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains a visitor to extract the include directives.
*/
module cpptooling.analyzer.clang.include_visitor;

import std.typecons : Nullable;
import std.algorithm : until, filter;

import clang.Cursor : Cursor;
import clang.c.Index;

import cpptooling.analyzer.clang.cursor_visitor;
import dextool.type : Path;

/** Extract the filenames from all `#include` preprocessor macros that are
 * found in the AST.
 *
 * Note that this is the filename inside the "", not the actual path on the
 * filesystem.
 *
 * Params:
 *  root = clang AST
 *  depth = how deep into the AST to analyze.
 */
Path[] extractIncludes(Cursor root, int depth = 2) {
    import std.array : appender;

    auto r = appender!(Path[])();

    foreach (c; root.visitBreathFirst.filter!(a => a.kind == CXCursorKind.inclusionDirective)) {
        r.put(Path(c.spelling));
    }

    return r.data;
}

/** Analyze the AST (root) to see if any of the `#include` fulfill the user supplied matcher.
 *
 * Params:
 *  root = clang AST
 *  depth = how deep into the AST to analyze.
 * Returns: the path to the header file that matched the predicate
 */
Nullable!Path hasInclude(alias matcher)(Cursor root, int depth = 2) @trusted {
    Nullable!Path r;

    foreach (c; root.visitBreathFirst.filter!(a => a.kind == CXCursorKind.inclusionDirective)) {
        if (matcher(c.spelling)) {
            r = Path(c.include.file.name);
            break;
        }
    }

    return r;
}
