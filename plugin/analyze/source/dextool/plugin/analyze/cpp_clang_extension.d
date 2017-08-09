/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file uses the same license as the C++ source code.
*/
module dextool.plugin.analyze.cpp_clang_extension;

import deimos.clang.index;

extern (C++, dextool_clang_extension) {
    extern (C++, McCabe) {
        extern (C++) struct Result {
            bool hasValue;
            /// McCabe complexity
            int value;
        }

        /** Calculate the McCabe complexity.
         *
         * Valid cursors are those with a body.
         * decl.isDefinition must be true.
         *
         * Tested CXCursor kinds that are definitions:
         *  - FunctionDecl
         *  - ConversionFunction
         *  - Constructor
         *  - Destructor
         *  - CXXMethod
         */
        extern (C++) Result calculate(CXCursor decl);
    }
}
