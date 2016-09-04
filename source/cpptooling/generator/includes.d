// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.generator.includes;

import dsrcgen.cpp : CppModule;

@safe:

/** Include headers as if they are C code.
 *
 * Wrapped in extern "C" to ensure C binding of the includes.
 */
void generateWrapIncludeInExternC(ControllerT, ParamT)(ControllerT ctrl, ParamT params,
        CppModule hdr) {
    import std.path : baseName;

    if (ctrl.doIncludeOfPreIncludes) {
        hdr.include(params.getFiles.pre_incl.baseName);
    }

    auto extern_c = hdr.suite("extern \"C\"");
    extern_c.suppressIndent(1);

    foreach (incl; params.getIncludes) {
        extern_c.include(cast(string) incl);
    }

    if (ctrl.doIncludeOfPostIncludes) {
        hdr.include(params.getFiles.post_incl.baseName);
    }

    hdr.sep(2);
}

/** Normal, unmodified include directives.
 *
 * Compared to generateC there are no special wrapping extern "C" wrapping.
 */
void generateIncludes(ControllerT, ParamT)(ControllerT ctrl, ParamT params, CppModule hdr) {
    import std.path : baseName;

    if (ctrl.doIncludeOfPreIncludes) {
        hdr.include(params.getFiles.pre_incl.baseName);
    }

    foreach (incl; params.getIncludes) {
        hdr.include(cast(string) incl);
    }

    if (ctrl.doIncludeOfPostIncludes) {
        hdr.include(params.getFiles.post_incl.baseName);
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
