/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Logging utilities used to avoid template bloat by only instansiating the logger
template one time by taking func and line as runtime parameters.
*/
module dextool.logger;

static import std.experimental.logger;

/// Only use via the aliases
auto internalLog(alias level)(const(char)[] txt, const uint indent = 0,
        string func = __FUNCTION__, uint line = __LINE__) nothrow @safe {
    import std.algorithm : min;
    import std.array : array;
    import std.range : repeat;

    immutable indent_prep = repeat(' ', 1024).array();

    try {
        string indent_ = indent_prep[0 .. min(indent_prep.length, indent)];
        () @trusted{
            std.experimental.logger.logf!(-1, "", "", "", "")(level,
                    "%d%s %s [%s:%d]", indent, indent_, txt, func, line);
        }();
    }
    catch (Exception ex) {
    }
}

alias trace = internalLog!(std.experimental.logger.LogLevel.trace);
alias info = internalLog!(std.experimental.logger.LogLevel.info);
alias error = internalLog!(std.experimental.logger.LogLevel.error);
alias fatal = internalLog!(std.experimental.logger.LogLevel.fatal);
