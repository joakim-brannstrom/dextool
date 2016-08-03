/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Most code in this file is from dstep/unit_tests/Common.d
*/
module test.clang_util;

public import cpptooling.analyzer.clang.context : ClangContext;

auto makeContext(string c, string[] args = null) {
    return ClangContext.fromString(c, args ~ ["-fsyntax-only"]);
}
