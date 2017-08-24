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

import std.algorithm : until, filter;

import clang.Cursor : Cursor;
import deimos.clang.index;

import cpptooling.analyzer.clang.cursor_visitor;
import dextool.type : FileName;

/** Extract the filenames from all `#include` preprocessor macros that are
 * found in the AST.
 *
 * Params:
 *  root = clang AST
 *  depth = how deep into the AST to analyze.
 */
FileName[] extractIncludes(Cursor root, int depth = 2) {
    import std.array : appender;

    auto r = appender!(FileName[])();

    foreach (c; root.visitBreathFirst.filter!(
            a => a.kind == CXCursorKind.CXCursor_InclusionDirective)) {
        r.put(FileName(c.spelling));
    }

    return r.data;
}

/** Analyze the AST (root) to see if any of the `#include` fulfill the user supplied matcher.
 *
 * Params:
 *  root = clang AST
 *  depth = how deep into the AST to analyze.
 */
bool hasInclude(alias matcher)(Cursor root, int depth = 2) @trusted {
    foreach (c; root.visitBreathFirst.filter!(
            a => a.kind == CXCursorKind.CXCursor_InclusionDirective)) {
        if (matcher(c.spelling)) {
            return true;
        }
    }

    return false;
}
