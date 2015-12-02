// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/
module cpptooling.generator.includes;

import dsrcgen.cpp : CppModule;

@safe:

/** Include headers as if they are C code.
 *
 * Wrapped in extern "C" to ensure C binding of the includes.
 */
void generateC(ControllerT, ParamT)(ControllerT ctrl, ParamT params, CppModule hdr) {
    import std.path : baseName;
    import cpptooling.utility.conv : str;

    if (ctrl.doIncludeOfPreIncludes) {
        hdr.include(params.getFiles.pre_incl.str.baseName);
    }

    auto extern_c = hdr.suite("extern \"C\"");
    extern_c.suppressIndent(1);

    foreach (incl; params.getIncludes) {
        extern_c.include(cast(string) incl);
    }

    if (ctrl.doIncludeOfPostIncludes) {
        hdr.include(params.getFiles.post_incl.str.baseName);
    }

    hdr.sep(2);
}

/** Normal, unmodified include directives.
 *
 * Compared to generateC there are no special wrapping extern "C" wrapping.
 */
void generate(ControllerT, ParamT)(ControllerT ctrl, ParamT params, CppModule hdr) {
    import std.path : baseName;
    import cpptooling.utility.conv : str;

    if (ctrl.doIncludeOfPreIncludes) {
        hdr.include(params.getFiles.pre_incl.str.baseName);
    }

    foreach (incl; params.getIncludes) {
        hdr.include(cast(string) incl);
    }

    if (ctrl.doIncludeOfPostIncludes) {
        hdr.include(params.getFiles.post_incl.str.baseName);
    }

    hdr.sep(2);
}

string convToIncludeGuard(FileT)(FileT fname) {
    import std.string : translate;
    import std.path : baseName;

    // dfmt off
    dchar[dchar] table = [
        '.' : '_',
        '-' : '_',
        '/' : '_'];
    // dfmt on

    return translate((cast(string) fname).baseName, table);
}

auto generatetPreInclude(FileT)(FileT fname) {
    import dsrcgen.cpp : CppHModule;

    auto o = CppHModule(convToIncludeGuard(fname));
    auto c = new CppModule;
    c.stmt("#undef __cplusplus")[$.end = ""];
    o.content.append(c);

    return o;
}

auto generatePostInclude(FileT)(FileT fname) {
    import dsrcgen.cpp : CppHModule;

    auto o = CppHModule(convToIncludeGuard(fname));
    auto c = new CppModule;
    c.define("__cplusplus");
    o.content.append(c);

    return o;
}
