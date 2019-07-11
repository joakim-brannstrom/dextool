/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.type_logger;

import clang.Type : Type;

/// Log a clang Type object if compiled with debug.
void logType(ref Type type, in uint indent = 0, string func = __FUNCTION__, uint line = __LINE__) {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.info : abilities;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent).array();
        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d%s %s|%s|%s|%s|%s [%s:%d]",
             indent,
             indent_,
             type.cursor.usr,
             type.kind,
             abilities(type),
             type.isValid ? "valid" : "invalid",
             type.typeKindSpelling,
             func,
             line);
    }
    // dfmt on
}
