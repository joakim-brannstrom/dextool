// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Logging utilities used to avoid template bloat by only instansiating the logger
template one time by taking func and line as runtime parameters.
*/
module cpptooling.utility.logger;

static import std.experimental.logger;

auto internalLog(alias level)(const(char)[] txt, in uint indent = 0,
        string func = __FUNCTION__, uint line = __LINE__) nothrow {
    import std.array : array;
    import std.range : repeat;

    try {
        string indent_ = repeat(' ', indent).array();
        std.experimental.logger.logf!(-1, "", "", "", "")(level,
                "%d%s %s [%s:%d]", indent, indent_, txt, func, line);
    }
    catch (Exception ex) {
    }
}

alias trace = internalLog!(std.experimental.logger.LogLevel.trace);
alias info = internalLog!(std.experimental.logger.LogLevel.info);
alias error = internalLog!(std.experimental.logger.LogLevel.error);
alias fatal = internalLog!(std.experimental.logger.LogLevel.fatal);
