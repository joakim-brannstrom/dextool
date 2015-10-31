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
module wipapp.wip_main;

import logger = std.experimental.logger;

import cpptooling.analyzer.clang.context;
import cpptooling.analyzer.clang.visitor;
import cpptooling.data.representation : AccessType;
import cpptooling.utility.clang : visitAst, logNode;

version (unittest) {
} else {
    int main(string[] args) {
        import std.stdio : writeln;

        logger.globalLogLevel(logger.LogLevel.all);
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

        ParseContext foo;
        foo.visit(file_ctx.cursor);
        writeln("Content from root: ", foo.root.toString);

        return 0;
    }
}
