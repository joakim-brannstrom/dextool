/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Most code in this file is from dstep/unit_tests/Common.d
*/
module test.clang_util;

import std.typecons : Flag, Yes, No;

public import cpptooling.analyzer.clang.context : ClangContext;

auto makeContext(string c, string[] args = null) {
    return ClangContext.fromString(c, args ~ ["-fsyntax-only"]);
}

auto makeInMemorySource(string filename, string content) {
    import std.string : toStringz;
    import deimos.clang.index : CXUnsavedFile;

    return CXUnsavedFile(filename.toStringz, content.ptr, content.length);
}

Flag!"hasError" checkForCompilerErrors(ref ClangContext ctx) {
    import cpptooling.analyzer.clang.context : hasParseErrors, logDiagnostic;

    if (ctx.hasParseErrors) {
        logDiagnostic(ctx);

        return Yes.hasError;
    }

    return No.hasError;
}
