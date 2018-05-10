/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.logger_conf;

import std.algorithm : among;
import std.stdio : writeln, writefln, stderr, stdout;

import logger = std.experimental.logger;

class SimpleLogger : logger.Logger {
    import std.conv;

    int line = -1;
    string file = null;
    string func = null;
    string prettyFunc = null;
    string msg = null;
    logger.LogLevel lvl;

    this(const logger.LogLevel lv = logger.LogLevel.info) {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        this.line = payload.line;
        this.file = payload.file;
        this.func = payload.funcName;
        this.prettyFunc = payload.prettyFuncName;
        this.lvl = payload.logLevel;
        this.msg = payload.msg;

        auto out_ = stderr;

        if (payload.logLevel.among(logger.LogLevel.info, logger.LogLevel.trace)) {
            out_ = stdout;
        }

        out_.writefln("%s: %s", text(this.lvl), this.msg);
    }
}

class DebugLogger : logger.Logger {
    import std.conv;

    int line = -1;
    string file = null;
    string func = null;
    string prettyFunc = null;
    string msg = null;
    logger.LogLevel lvl;

    this(const logger.LogLevel lv = logger.LogLevel.trace) {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        this.line = payload.line;
        this.file = payload.file;
        this.func = payload.funcName;
        this.prettyFunc = payload.prettyFuncName;
        this.lvl = payload.logLevel;
        this.msg = payload.msg;

        auto out_ = stderr;

        if (payload.logLevel.among(logger.LogLevel.info, logger.LogLevel.trace)) {
            out_ = stdout;
        }

        if (this.line == -1) {
            out_.writefln("%s: %s", text(this.lvl), this.msg);
        } else {
            // Example of standard: 2016-05-01T22:31:54.019:type.d:retrieveType:159 c:@S@Foo:struct Foo
            out_.writefln("%s: %s [%s:%d]", text(this.lvl), this.msg, this.func, this.line);
        }
    }
}

enum ConfigureLog {
    default_,
    info,
    debug_,
}

void confLogLevel(ConfigureLog conf) {
    import std.exception;
    import std.experimental.logger.core : sharedLog;

    try {
        final switch (conf) {
        case ConfigureLog.default_:
            goto case;
        case ConfigureLog.info:
            logger.globalLogLevel(logger.LogLevel.info);
            auto simple_logger = new SimpleLogger();
            logger.sharedLog(simple_logger);
            break;
        case ConfigureLog.debug_:
            logger.globalLogLevel(logger.LogLevel.all);
            auto logger_ = new DebugLogger();
            logger.sharedLog(logger_);
            break;
        }
    } catch (Exception ex) {
        collectException(logger.error("Failed to configure logging level"));
        throw ex;
    }
}
