/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Oct 1, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */

module clang.Index;

import deimos.clang.index;

struct Index {
    import std.typecons : RefCounted;
    import clang.Util;

    static private struct ContainIndex {
        mixin CX!("Index");

        ~this() {
            dispose();
        }
    }

    RefCounted!ContainIndex cx;
    alias cx this;

    this(bool excludeDeclarationsFromPCH, bool displayDiagnostics) {
        cx = clang_createIndex(excludeDeclarationsFromPCH ? 1 : 0, displayDiagnostics ? 1 : 0);
    }
}
