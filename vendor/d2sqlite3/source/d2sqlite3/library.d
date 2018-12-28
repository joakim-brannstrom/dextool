/++
Miscellaneous SQLite3 library functions.

Authors:
    Nicolas Sicard (biozic) and other contributors at $(LINK https://github.com/biozic/d2sqlite3)

Copyright:
    Copyright 2011-18 Nicolas Sicard.

License:
    $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+/
module d2sqlite3.library;

import d2sqlite3.sqlite3;
import d2sqlite3.database : SqliteException;
import std.exception : enforce;
import std.string : format;

/++
Gets the library's version string (e.g. "3.8.7"), version number (e.g. 3_008_007)
or source ID.

These values are returned by the linked SQLite C library. They can be checked against
the values of the enums defined by the `d2sqlite3` package (`SQLITE_VERSION`,
`SQLITE_VERSION_NUMBER` and `SQLITE_SOURCE_ID`).

See_Also: $(LINK http://www.sqlite.org/c3ref/libversion.html).
+/
string versionString() {
    import std.conv : to;

    return sqlite3_libversion().to!string;
}

/// Ditto
int versionNumber() nothrow {
    return sqlite3_libversion_number();
}

/// Ditto
string sourceID() {
    import std.conv : to;

    return sqlite3_sourceid().to!string;
}

/++
Tells whether SQLite was compiled with the thread-safe options.

See_also: $(LINK http://www.sqlite.org/c3ref/threadsafe.html).
+/
bool threadSafe() nothrow {
    return cast(bool) sqlite3_threadsafe();
}

/++
Manually initializes (or shuts down) SQLite.

SQLite initializes itself automatically on the first request execution, so this
usually wouldn't be called. Use for instance before a call to config().
+/
void initialize() {
    auto result = sqlite3_initialize();
    enforce(result == SQLITE_OK, new SqliteException("Initialization: error %s".format(result)));
}
/// Ditto
void shutdown() {
    auto result = sqlite3_shutdown();
    enforce(result == SQLITE_OK, new SqliteException("Shutdown: error %s".format(result)));
}

/++
Sets a configuration option.

Use before initialization, e.g. before the first
call to initialize and before execution of the first statement.

See_Also: $(LINK http://www.sqlite.org/c3ref/config.html).
+/
void config(Args...)(int code, Args args) {
    auto result = sqlite3_config(code, args);
    enforce(result == SQLITE_OK, new SqliteException("Configuration: error %s".format(result)));
}

/++
Tests if an SQLite compile option is set

See_Also: $(LINK http://sqlite.org/c3ref/compileoption_get.html).
+/
bool isCompiledWith(string option) {
    import std.string : toStringz;

    return cast(bool) sqlite3_compileoption_used(option.toStringz);
}
///
version (SqliteEnableUnlockNotify) unittest {
    assert(isCompiledWith("SQLITE_ENABLE_UNLOCK_NOTIFY"));
    assert(!isCompiledWith("SQLITE_UNKNOWN_COMPILE_OPTION"));
}
