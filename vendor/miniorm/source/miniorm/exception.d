///
module miniorm.exception;

import logger = std.experimental.logger;

import d2sqlite3;

import miniorm.api : RefCntStatement;
import miniorm.queries : Bind;

class MiniormException : Exception {
    SqliteException sqliteException;
    this(string fq, SqliteException e) {
        sqliteException = e;
        import std.format;

        super(format("%s\nfull query: %s", e.msg, fq));
    }
}

class MiniormBindException : Exception {
    this(string fq, size_t actualBind, size_t expectedBind) {
        import std.format : format;

        super(format!"Expected %s parameters but %s provided\nfull query: %s"(expectedBind,
                actualBind, fq));
    }
}

auto executeCheck(Args...)(RefCntStatement stmt, string query, Bind[] binds, auto ref Args args) {
    if (binds.length != Args.length) {
        throw new MiniormBindException(query, args.length, binds.length);
    }

    try {
        int idx;
        static foreach (a; args) {
            stmt.get.bind(binds[idx++].toString, a);
        }
        return stmt.get.execute;
    } catch (SqliteException e)
        throw new MiniormException(query, e);
}
