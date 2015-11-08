/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg, Joakim Brännström (joakim.brannstrom dottli gmx.com)
 * Version: 1.1
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 * History:
 *  1.0 initial release. 2012-01-29 $(BR)
 *    Jacob Carlborg
 *
 *  1.1 additional features missing compared to cindex.py. 2015-03-07 $(BR)
 *    Joakim Brännström
 */

module clang.File;

import core.stdc.time;

import deimos.clang.index;

import clang.Util;

/// The File class represents a particular source file that is part of a translation unit.
struct File {
    mixin CX;

    /// Returns: the complete file and path name of the file.
    @property string name() @trusted {
        return toD(clang_getFileName(cx));
    }

    /// Return the last modification time of the file.
    @property time_t time() @trusted {
        return clang_getFileTime(cx);
    }
}
