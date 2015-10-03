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
module cpptooling.generator.stub.stub;

import logger = std.experimental.logger;

interface StubController {
    /// Process AST node belonging to filename.
    bool doFile(string filename);

    /// Process AST node that is a class.
    bool doClass();

    /// File to include in the generated header.
    StubGenerator.HdrFilename getIncludeFile();

    //ClassController getClass();
}

struct StubGenerator {
    import std.typecons : Typedef;

    import cpptooling.data.representation : CppRoot;
    import cpptooling.utility.conv : str;
    import dsrcgen.cpp : CppModule, CppHModule;

    alias HdrFilename = Typedef!(string, string.init, "HdrFilename");

    /**
     * Params:
     *  prefix = prefix to use for the name of the stub class.
     */
    this(StubController ctrl) {
        this.ctrl = ctrl;
        this.hdr = new CppModule;
        this.impl = new CppModule;
    }

    void translate(CppRoot) {
    }

    /** Generate the C++ header file of the stub.
     * Params:
     *  filename = intended output filename, used for ifdef guard.
     */
    string outputHdr(HdrFilename filename) {
        import std.string : translate;

        dchar[dchar] table = ['.' : '_', '-' : '_'];

        ///TODO add user defined header.
        auto o = CppHModule(translate(filename.str, table));
        o.content.include(ctrl.getIncludeFile.str);
        o.content.sep(2);
        o.content.append(this.hdr);

        return o.render;
    }

    string outputImpl(HdrFilename filename) {
        ///TODO add user defined header.
        auto o = new CppModule;
        o.suppressIndent(1);
        o.include(filename.str);
        o.sep(2);
        o.append(impl);

        return o.render;
    }

private:
    CppModule hdr;
    CppModule impl;

    StubController ctrl;
}
