///
module miniorm.exception;

import d2sqlite3;

class MiniormException : Exception {
    SqliteException sqliteException;
    this(string fq, SqliteException e) {
        sqliteException = e;
        import std.format;

        super(format("%s\nfull query: %s", e.msg, fq));
    }
}

auto executeCheck(ref Database db, string queryStr) {
    try
        return db.execute(queryStr);
    catch (SqliteException e)
        throw new MiniormException(queryStr, e);
}

auto runCheck(ref Database db, string queryStr) {
    try
        return db.run(queryStr);
    catch (SqliteException e)
        throw new MiniormException(queryStr, e);
}
