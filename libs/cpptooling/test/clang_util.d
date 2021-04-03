/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Most code in this file is from dstep/unit_tests/Common.d
*/
module test.clang_util;

import std.typecons : Flag, Yes, No;

public import libclang_ast.context : ClangContext;

static import clang.TranslationUnit;

Flag!"hasError" checkForCompilerErrors(ref clang.TranslationUnit.TranslationUnit ctx) {
    import libclang_ast.check_parse_result : hasParseErrors, logDiagnostic;

    if (ctx.hasParseErrors) {
        logDiagnostic(ctx);

        return Yes.hasError;
    }

    return No.hasError;
}
