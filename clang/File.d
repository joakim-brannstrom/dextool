/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg, Joakim Brännström (joakim.brannstrom dottli gmx.com)
 * Version: 1.1+
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 * History:
 *  1.0 initial release. 2012-01-29 $(BR)
 *    Jacob Carlborg
 *
 *  1.1+ additional features missing compared to cindex.py. 2015-03-07 $(BR)
 *    Joakim Brännström
 */

module clang.File;

import core.stdc.time;

import clang.c.Index;

import clang.Util;

/// The File class represents a particular source file that is part of a translation unit.
struct File {
    mixin CX;

    /// Returns: the complete file and path name of the file.
    @property string name() const @trusted {
        // OK to throw away const because the C functions do not change the ptr.
        return toD(clang_getFileName(cast(CType) cx));
    }

    /// Return the last modification time of the file.
    @property time_t time() const @trusted {
        // OK to throw away const because the C functions do not change the ptr.
        return clang_getFileTime(cast(CType) cx);
    }

    string toString() @safe const {
        return name;
    }
}
