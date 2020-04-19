/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains convenient functions for logging some meta data about a
cursor for debugging purpose.
*/
module cpptooling.analyzer.clang.cursor_logger;

import clang.Cursor : Cursor;
import clang.Visitor : Visitor;

/// Log information of a cursor.
void logNode(ref const Cursor c, const int indent = 0, const string func = __FUNCTION__,
        const uint line = __LINE__) @trusted {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.Cursor : dump;
    import clang.info : abilities;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent).array();
        auto loc = c.location;
        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d %s%s|%s|%s|%s:%d:%d [%s:%d]",
             indent,
             indent_,
             dump(c),
             c.displayName,
             abilities(c),
             loc.file,
             loc.spelling.line,
             loc.spelling.column,
             func,
             line);
    }
    // dfmt on
}

/// logNode can't take a rvalue so creating a temporary and then logging.
/// -3 because there are 3 lines until the call to logNode. By subtracting it is
/// kept semantic equivalent to the mixin line.
template mixinNodeLog() {
    enum mixinNodeLog = q{debug {
            {
                auto c = v.cursor;
                logNode(c, indent, __FUNCTION__, __LINE__-3);
            }
        }
    };
}
