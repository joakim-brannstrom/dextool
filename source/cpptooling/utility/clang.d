/**
Copyright: Copyright (c) 2015-2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.utility.clang;

import std.traits : ReturnType;

import clang.Cursor : Cursor;
import clang.Visitor : Visitor;

/// Log information of a cursor.
void logNode(ref const(Cursor) c, in int indent = 0, string func = __FUNCTION__, uint line = __LINE__) @trusted {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.Cursor : dump;
    import clang.info : abilities;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent).array();
        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d %s%s|%s|%s|%s:%d:%d [%s:%d]",
             indent,
             indent_,
             dump(c),
             c.displayName,
             abilities(c),
             c.location.file,
             c.location.spelling.line,
             c.location.spelling.column,
             func,
             line);
    }
    // dfmt on
}

/// logNode can't take a rvalue so creating a temporary and then logging.
template mixinNodeLog() {
    enum mixinNodeLog = q{debug {
            {
                auto c = v.cursor;
                logNode(c, indent);
            }
        }
    };
}
