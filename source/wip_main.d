/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module app;

import std.conv;
import std.typecons : Nullable;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;
import containers = generator.analyze.containers;
import wip = generator.analyze.wip;
import generator.clangcontext;
import generator.analyzer : visitAst, IdStack, logNode, VisitNodeModule,
    VisitNodeDepth;

/** The constructor is disabled to force the class to be in a consistent state.
 * static make to create ClassVisitor objects to avoid the unnecessary storage
 * of a Cursor but still derive parameters from the Cursor.
 */
struct ClassVisitor {
    import generator.analyze.containers : CppClass, CppClassName, VirtualType,
        CppVirtualClass;

    /** By making ClassVisitor via this static function it is guaranteed that
     * the same Cursor that the name and virtuality is derived from is the same
     * that is used to visit the AST.
     */
    static ClassVisitor make(ref Cursor c) {
        auto name = CppClassName(c.spelling);
        auto isVirtual = CppVirtualClass(c.isVirtualBase ? VirtualType.Pure : VirtualType.No);

        auto r = ClassVisitor(name, isVirtual);
        r.visit(c);
        return r;
    }

    @disable this();

    private this(CppClassName name, CppVirtualClass virtual) {
        data = CppClass(name, virtual);
    }

    void visit(ref Cursor c) {
        if (!c.isDefinition) {
            return;
        }
        wip.visitAst!(typeof(this))(c, this);
    }

    bool apply(ref Cursor child, ref Cursor parent) {
        bool descend = true;

        switch (child.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            break;
        case CXCursor_Constructor:
            break;
        case CXCursor_Destructor:
            break;
        case CXCursor_CXXAccessSpecifier:
            break;
        default:
            break;
        }
        return descend;
    }

    CppClass data;
}

struct EntryContext {
    private VisitNodeDepth depth_;
    alias depth_ this;

    void visit(Cursor cursor) {
        wip.visitAst!(typeof(this))(cursor, this);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        bool descend = true;
        logNode(c, depth);
        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            descend = false;
            break;

        default:
            break;
        }

        return descend;
    }

    containers.Root root;
}

int main(string[] args) {
    logger.info("WIP mode");
    if (args.length < 2) {
        logger.info("Unittesting");
        return 0;
    }

    auto infile = to!string(args[1]);
    auto file_ctx = new ClangContext(infile);
    file_ctx.logDiagnostic;
    if (file_ctx.hasParseErrors)
        return 1;

    logger.infof("Testing '%s'", infile);

    EntryContext foo;
    foo.visit(file_ctx.cursor);

    return 0;
}
