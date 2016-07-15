// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.utility.clang;

import std.traits : ReturnType;

import clang.Cursor : Cursor;
import clang.Visitor : Visitor;

void logNode(ref const(Cursor) c, in int indent = 0, string func = __FUNCTION__, uint line = __LINE__) @trusted {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.Cursor : dump;
    import clang.info;

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
             c.abilities,
             c.location.file,
             c.location.spelling.line,
             c.location.spelling.column,
             func,
             line);
    }
    // dfmt on
}

template mixinNodeLog() {
    enum mixinNodeLog = q{debug {
            {
                auto c = v.cursor;
                logNode(c, indent);
            }
        }
    };
}
