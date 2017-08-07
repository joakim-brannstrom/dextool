/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file uses the same license as the C++ source code.
*/
module dextool.plugin.analyze.cpp_clang_extension;

import deimos.clang.index;

extern (C++, dextool_clang_extension) {
    extern (C++) void f(const(char)* s);
    extern (C++, McCabe) {
        extern (C++) struct Result {
            bool hasValue;
            int value;
        }

        extern (C++) Result calculate(CXCursor decl);
    }
}
