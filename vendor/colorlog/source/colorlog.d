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

/// The verbosity level of the logging to use.
enum VerboseMode {
    /// Warning+
    minimal,
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
    switch (mode) {
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
    default:
        logger.globalLogLevel = logger.LogLevel.info;
        logger.sharedLog = new SimpleLogger(logger.LogLevel.info);
    }
}

@("shall be @safe to configure the logger")
@safe unittest {
    auto old_level = logger.globalLogLevel;
    auto old_log = logger.sharedLog;
    scope (exit) {
        logger.globalLogLevel = old_level;
        logger.sharedLog = old_log;
    }

    confLogger(VerboseMode.info);
}

private template BaseColor(int n) {
    enum BaseColor : int {
        none = 39 + n,

        black = 30 + n,
        red = 31 + n,
        green = 32 + n,
        yellow = 33 + n,
        blue = 34 + n,
        magenta = 35 + n,
        cyan = 36 + n,
        white = 37 + n,

        lightBlack = 90 + n,
        lightRed = 91 + n,
        lightGreen = 92 + n,
        lightYellow = 93 + n,
        lightBlue = 94 + n,
        lightMagenta = 95 + n,
        lightCyan = 96 + n,
        lightWhite = 97 + n,
    }
}

alias Color = BaseColor!0;
alias Background = BaseColor!10;

enum Mode {
    none = 0,
    bold = 1,
    underline = 4,
    blink = 5,
    swap = 7,
    hide = 8,
}

struct ColorImpl {
    import std.format : FormatSpec;

    private {
        string text;
        Color fg_;
        Background bg_;
        Mode mode_;
    }

    this(string txt) @safe pure nothrow @nogc {
        text = txt;
    }

    this(string txt, Color c) @safe pure nothrow @nogc {
        text = txt;
        fg_ = c;
    }

    auto fg(Color c_) @safe pure nothrow @nogc {
        this.fg_ = c_;
        return this;
    }

    auto bg(Background c_) @safe pure nothrow @nogc {
        this.bg_ = c_;
        return this;
    }

    auto mode(Mode c_) @safe pure nothrow @nogc {
        this.mode_ = c_;
        return this;
    }

    string toString() @safe const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) @safe const{ buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        if (!_printColors || (fg_ == Color.none && bg_ == Background.none && mode_ == Mode.none))
            put(w, text);
        else
            formattedWrite(w, "\033[%d;%d;%dm%s\033[0m", mode_, fg_, bg_, text);
    }
}

auto color(string s, Color c = Color.none) @safe pure nothrow @nogc {
    return ColorImpl(s, c);
}

@("shall be safe/pure/nothrow/nogc to color a string")
@safe pure nothrow @nogc unittest {
    auto s = "foo".color(Color.red).bg(Background.black).mode(Mode.bold);
}

@("shall be safe to color a string")
@safe unittest {
    auto s = "foo".color(Color.red).bg(Background.black).mode(Mode.bold).toString;
}

/** Whether to print text with colors or not
 *
 * Defaults to true but will be set to false in initColors() if stdout or
 * stderr are not a TTY (which means the output is probably being piped and we
 * don't want ASCII escape chars in it)
*/
private shared bool _printColors = true;
private shared bool _isColorsInitialized = false;

// The width of the prefix.
private immutable _prefixWidth = 8;

/** It will detect whether or not stdout/stderr are a console/TTY and will
 * consequently disable colored output if needed.
 *
 * Forgetting to call the function will result in ASCII escape sequences in the
 * piped output, probably an undesiderable thing.
 */
void initColors() @trusted {
    if (_isColorsInitialized)
        return;
    scope (exit)
        _isColorsInitialized = true;

    // Initially enable colors, we'll disable them during this functions if we
    // find any reason to
    _printColors = true;

    version (Windows) {
        _printColors = false;
    } else {
        import core.stdc.stdio;
        import core.sys.posix.unistd;

        if (!isatty(STDERR_FILENO) || !isatty(STDOUT_FILENO))
            _printColors = false;
    }
}

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
