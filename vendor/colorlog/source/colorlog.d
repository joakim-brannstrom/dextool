/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Handles console logging in pretty colors.

The module disables colors when stdout and stderr isn't a TTY that support
colors. This is to avoid ASCII escape sequences in piped output.

The logger named "_" is the default parent. It is, by default, not set to anything.
*/
module colorlog;

import logger = std.experimental.logger;
import std.array : empty;
import std.conv : to;
import std.experimental.logger : LogLevel;
import std.stdio : writefln, stderr, stdout;

public import my.term_color;

enum RootLogger = "_";

/// The verbosity level of the logging to use.
enum VerboseMode {
    /// Info+
    info,
    /// Trace+
    trace,
    /// Warnings+
    warning,
}

LogLevel toLogLevel(VerboseMode mode) @safe pure nothrow @nogc {
    final switch (mode) {
    case VerboseMode.info:
        return logger.LogLevel.info;
    case VerboseMode.trace:
        return logger.LogLevel.all;
    case VerboseMode.warning:
        return logger.LogLevel.warning;
    }
}

/** Configure `std.experimental.logger` `sharedLog` with a colorlog instance
 * and register it with name "_".
 */
void confLogger(VerboseMode mode) @safe {
    logger.globalLogLevel = toLogLevel(mode);

    final switch (mode) {
    case VerboseMode.info:
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

    () @trusted { register(logger.sharedLog, RootLogger); }();
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

        out_.writefln("%s: %s [%s:%d]", payload.logLevel.to!string.color(use_color)
                .bg(use_bg).mode(use_mode), payload.msg, payload.funcName, payload.line);
    }
}

/// A string mixin to create a SimpleLogger for the module.
string mixinModuleLogger(logger.LogLevel defaultLogLvl = logger.LogLevel.all) @safe pure {
    return "shared static this() { import std.experimental.logger : LogLevel; make!SimpleLogger(LogLevel."
        ~ defaultLogLvl.to!string ~ "); }";
}

/// Register a logger for the module and make it configurable from "outside" via the registry.
void register(logger.Logger logger, string name = __MODULE__, string parent = RootLogger) {
    synchronized (poolLock) {
        loggerParent[name] = parent;
        loggers[name] = cast(shared) logger;
    }
}

/// Create a logger for the module and make it configurable from "outside" via the registry.
void make(LoggerT)(const logger.LogLevel lvl = logger.LogLevel.all,
        string name = __MODULE__, string parent = RootLogger) @trusted {
    register(new LoggerT(lvl), name, parent);
}

/// Returns: the name of all registered loggers.
string[] getRegisteredLoggers() @trusted {
    import std.array : appender;

    auto app = appender!(string[])();
    synchronized (poolLock) {
        foreach (a; (cast() loggers).byKey)
            app.put(a);
    }

    return app.data;
}

/// Remove all registered loggers.
void clearAllLoggers() @trusted {
    synchronized (poolLock) {
        loggers = null;
        loggerParent = null;
    }
}

enum SpanMode {
    /// Set only the specified logger.
    single,
    /// Set the logger and all its children.
    depth
}

/// Set the log level for `name`.
void setLogLevel(const string name, const logger.LogLevel lvl, const SpanMode span = SpanMode
        .single) @trusted {
    static void setSingle(const string name, const logger.LogLevel lvl) {
        if (auto v = name in loggers) {
            auto uv = cast()*v;
            uv.logLevel = lvl;
        } else {
            throw new UnknownLogger("no such logger registered: " ~ name);
        }
    }

    static void depth(string startName, const logger.LogLevel lvl) {
        import std.algorithm : filter, map;
        import my.set;

        Set!string visited;
        auto queue = [startName];

        while (!queue.empty) {
            const curr = queue[0];
            foreach (a; (cast() loggerParent).byKeyValue
                    .filter!(a => a.value == curr)
                    .filter!(a => a.key !in visited)) {
                setSingle(a.key, lvl);
                queue ~= a.key;
                visited.add(a.key);
            }

            queue = queue[0 .. $ - 1];
        }
    }

    synchronized (poolLock) {
        final switch (span) {
        case SpanMode.single:
            setSingle(name, lvl);
            break;
        case SpanMode.depth:
            setSingle(name, lvl);
            depth(name, lvl);
            break;
        }
    }
}

/// Set the log level for all loggers in `names`.
void setLogLevel(const string[] names, const logger.LogLevel lvl,
        const SpanMode span = SpanMode.single) @safe {
    foreach (a; names)
        setLogLevel(a, lvl, span);
}

/// Set the log level for all loggers in `names`.
void setLogLevel(const NameLevel[] names, const SpanMode span = SpanMode.single) @safe {
    foreach (a; names)
        setLogLevel(a.name, a.level, span);
}

/** Log a mesage to the specified logger.
 *
 * This only takes the global lock one time and then cache the logger.
 */
logger.Logger log(string name = __MODULE__)() @trusted {
    static logger.Logger local;

    if (local !is null)
        return local;

    synchronized (poolLock) {
        if (auto v = name in loggers) {
            local = cast()*v;
            return cast()*v;
        }
    }

    throw new UnknownLogger("no such logger registered: " ~ name);
}

struct NameLevel {
    string name;
    LogLevel level;
}

/// Parse a comma+equal separated string for logger names that can be used with `setLogLevel`.
NameLevel[] parseLogNames(string arg, logger.LogLevel defaultLogLvl = logger.LogLevel.all) @safe pure {
    import std.algorithm : splitter, joiner, map;
    import std.array : array;
    import std.string : split;

    NameLevel[] conv(string s) {
        try {
            auto sp = split(s, '=');
            if (sp.length != 2)
                return [NameLevel(s, defaultLogLvl)];
            return [NameLevel(sp[0], sp[1].to!(logger.LogLevel))];
        } catch (Exception e) {
        }
        return NameLevel[].init;
    }

    return arg.splitter(',').map!conv.joiner.array;
}

/** Always takes the global lock to find the logger.
 *
 * This is safe to use whenever because if they logger is replaced it will be
 * returned.  Normally though this feature isn't needed. Normally all loggers
 * are registered during module initialization and then they are not changed.
 */
logger.Logger logSlow(string name = __MODULE__)() @trusted {
    synchronized (poolLock) {
        if (auto v = name in loggers) {
            return cast()*v;
        }
    }

    throw new UnknownLogger("no such logger registered: " ~ name);
}

/// Unknown logger.
class UnknownLogger : Exception {
    this(string msg, string file = __FILE__, int line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

@("shall instantiate a logger and register")
unittest {
    scope (exit)
        clearAllLoggers;
    make!TestLogger();
    assert([__MODULE__] == getRegisteredLoggers());
}

@("shall register a logger and register")
unittest {
    scope (exit)
        clearAllLoggers;
    register(new TestLogger);
    assert([__MODULE__] == getRegisteredLoggers());
}

@("shall log a message")
unittest {
    scope (exit)
        clearAllLoggers;
    make!TestLogger();

    logSlow.warning("hej");

    synchronized (poolLock) {
        assert(!((cast(TestLogger) loggers[__MODULE__]).lastMsg.empty), "no message logged");
    }
}

@("shall change the log level")
unittest {
    scope (exit)
        clearAllLoggers;
    make!TestLogger(logger.LogLevel.warning);
    make!TestLogger(logger.LogLevel.warning, "test", __MODULE__);

    setLogLevel(__MODULE__, logger.LogLevel.trace);

    logSlow.trace("hej");
    logSlow!"test".trace("hej");

    synchronized (poolLock) {
        assert(!((cast(TestLogger) loggers[__MODULE__]).lastMsg.empty),
                "message found when it shouldn't");
        assert(((cast(TestLogger) loggers["test"]).lastMsg.empty),
                "message found when it shouldn't");
    }
}

@("shall change the log level from parent and up")
unittest {
    scope (exit)
        clearAllLoggers;
    make!TestLogger(logger.LogLevel.warning);
    make!TestLogger(logger.LogLevel.warning, "test", __MODULE__);

    setLogLevel(__MODULE__, logger.LogLevel.trace, SpanMode.depth);

    logSlow.trace("hej");
    logSlow!"test".trace("hej");

    synchronized (poolLock) {
        assert(!((cast(TestLogger) loggers[__MODULE__]).lastMsg.empty),
                "message found when it shouldn't");
        assert(!((cast(TestLogger) loggers["test"]).lastMsg.empty),
                "message found when it shouldn't");
    }
}

@("shall parse a comma separate list")
unittest {
    assert(parseLogNames("hej=trace,foo") == [
            NameLevel("hej", logger.LogLevel.trace),
            NameLevel("foo", logger.LogLevel.all)
            ]);
}

private:

import core.sync.mutex : Mutex;

// The width of the prefix.
immutable _prefixWidth = 8;

// Mutex for the logger pool.
shared Mutex poolLock;
shared logger.Logger[string] loggers;
shared string[string] loggerParent;

shared static this() {
    poolLock = cast(shared) new Mutex();
}

class TestLogger : logger.Logger {
    this(const logger.LogLevel lvl = LogLevel.trace) @safe {
        super(lvl);
    }

    string lastMsg;

    override void writeLogMsg(ref LogEntry payload) @trusted {
        import std.format : format;

        lastMsg = format!"%s: %s [%s:%d]"(payload.logLevel, payload.msg,
                payload.funcName, payload.line);
    }
}
