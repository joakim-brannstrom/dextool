/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Handles console logging in pretty colors.

The module disables colors when stdout and stderr isn't a TTY that support
colors. This is to avoid ASCII escape sequences in piped output.
*/
module colorlog;

import std.stdio : writefln, stderr, stdout;
import logger = std.experimental.logger;
import std.experimental.logger : LogLevel;

public import my.term_color;

/// The verbosity level of the logging to use.
enum VerboseMode {
    /// Info+
    info,
    /// Trace+
    trace,
    /// Warnings+
    warning,
}

/** Configure `std.experimental.logger` with a colorlog instance.
 */
void confLogger(VerboseMode mode) @safe {
    final switch (mode) {
    case VerboseMode.info:
        logger.globalLogLevel = logger.LogLevel.info;
        logger.sharedLog = new SimpleLogger(logger.LogLevel.info);
        break;
    case VerboseMode.trace:
        logger.globalLogLevel = logger.LogLevel.all;
        logger.sharedLog = new DebugLogger(logger.LogLevel.all);
        break;
    case VerboseMode.warning:
        logger.globalLogLevel = logger.LogLevel.warning;
        logger.sharedLog = new SimpleLogger(logger.LogLevel.info);
        break;
    }
}

// The width of the prefix.
private immutable _prefixWidth = 8;

class SimpleLogger : logger.Logger {
    this(const LogLevel lvl = LogLevel.warning) @safe {
        super(lvl);
        initColors;
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        auto out_ = stderr;
        auto use_color = Color.red;
        auto use_mode = Mode.bold;
        const use_bg = Background.black;

        switch (payload.logLevel) {
        case LogLevel.trace:
            out_ = stdout;
            use_color = Color.white;
            use_mode = Mode.init;
            break;
        case LogLevel.info:
            out_ = stdout;
            use_color = Color.white;
            break;
        default:
        }

        import std.conv : to;

        out_.writefln("%s: %s", payload.logLevel.to!string.color(use_color)
                .bg(use_bg).mode(use_mode), payload.msg);
    }
}

class DebugLogger : logger.Logger {
    this(const logger.LogLevel lvl = LogLevel.trace) @safe {
        super(lvl);
        initColors;
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        auto out_ = stderr;
        auto use_color = Color.red;
        auto use_mode = Mode.bold;
        const use_bg = Background.black;

        switch (payload.logLevel) {
        case LogLevel.trace:
            out_ = stdout;
            use_color = Color.white;
            use_mode = Mode.init;
            break;
        case LogLevel.info:
            out_ = stdout;
            use_color = Color.white;
            break;
        default:
        }

        import std.conv : to;

        out_.writefln("%s: %s [%s:%d]", payload.logLevel.to!string.color(use_color)
                .bg(use_bg).mode(use_mode), payload.msg, payload.funcName, payload.line);
    }
}
