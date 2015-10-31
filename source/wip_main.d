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
import std.stdio;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;
import wip = generator.analyze.wip;
import generator.clangcontext;
import generator.analyzer : visitAst, IdStack, logNode, VisitNodeModule;

version (unittest) {
    import tested;

    shared static this() {
        import core.runtime;

        Runtime.moduleUnitTester = () => true;
    }
}

struct EntryContext {
    VisitNodeModule!CppModule visitor_stack;
    alias visitor_stack this;

    void traverse(Cursor cursor) {
        visitAst!(typeof(this))(cursor, this);
    }

    bool apply(Cursor c) {
        bool descend = true;
        logNode(c, depth);
        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            if (c.isDefinition) {
            }
            break;

        default:
            break;
        }

        return descend;
    }
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
    foo.traverse(file_ctx.cursor);

    return 0;
}
