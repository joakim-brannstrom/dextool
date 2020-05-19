/**
Copyright: Copyright (c) 2017, Oleg Butko. All rights reserved.
Copyright: Copyright (c) 2018-2019, Joakim Brännström. All rights reserved.
License: MIT
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
Author: Oleg Butko (deviator)
*/
module miniorm.api;

import core.time : dur;
import logger = std.experimental.logger;
import std.array : Appender;
import std.datetime : SysTime, Duration;
import std.range;

import miniorm.exception;
import miniorm.queries;

import d2sqlite3;

version (unittest) {
    import std.algorithm : map;
    import unit_threaded.assertions;
}

///
struct Miniorm {
    private LentCntStatement[string] cachedStmt;
    private size_t cacheSize = 128;
    /// True means that all queries are logged.
    private bool log_;

    ///
    private Database db;
    alias getUnderlyingDb this;

    ref Database getUnderlyingDb() return  {
        return db;
    }

    ///
    this(Database db) {
        this.db = db;
    }

    ///
    this(string path, int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) {
        this(Database(path, flags));
    }

    ~this() {
        cleanupCache;
    }

    /// Start a RAII handled transaction.
    Transaction transaction() {
        return Transaction(db);
    }

    void prepareCacheSize(size_t s) {
        cacheSize = s;
    }

    RefCntStatement prepare(string sql) {
        if (cachedStmt.length > cacheSize) {
            auto keys = appender!(string[])();
            foreach (p; cachedStmt.byKeyValue) {
                // the statement is currently not lent to any user.
                if (p.value.count == 0) {
                    keys.put(p.key);
                }
            }

            foreach (k; keys.data) {
                cachedStmt[k].stmt.finalize;
                cachedStmt.remove(k);
            }
        }

        if (auto v = sql in cachedStmt) {
            return RefCntStatement(*v);
        }
        auto r = db.prepare(sql);
        cachedStmt[sql] = LentCntStatement(r);
        return RefCntStatement(cachedStmt[sql]);
    }

    /// Toggle logging.
    void log(bool v) nothrow {
        this.log_ = v;
    }

    /// Returns: True if logging is activated
    private bool isLog() {
        return log_;
    }

    private void cleanupCache() {
        foreach (ref s; cachedStmt.byValue) {
            s.stmt.finalize;
        }
        cachedStmt = null;
    }

    void opAssign(ref typeof(this) rhs) {
        cleanupCache;
        db = rhs.db;
    }

    void run(string sql, bool delegate(ResultRange) dg = null) {
        if (isLog) {
            logger.trace(sql);
        }
        db.run(sql, dg);
    }

    void close() {
        cleanupCache;
        db.close();
    }

    size_t run(T, Args...)(Count!T v, auto ref Args args) {
        const sql = v.toSql.toString;
        if (isLog) {
            logger.trace(sql);
        }
        auto stmt = prepare(sql);
        return executeCheck(stmt, sql, v.binds, args).front.front.as!size_t;
    }

    auto run(T, Args...)(Select!T v, auto ref Args args) {
        import std.algorithm : map;
        import std.format : format;
        import std.range : inputRangeObject;

        const sql = v.toSql.toString;
        if (isLog) {
            logger.trace(sql);
        }

        auto stmt = prepare(sql);
        auto result = executeCheck(stmt, sql, v.binds, args);

        static T qconv(typeof(result.front) e) {
            import std.algorithm : min;
            import std.conv : to;
            import std.traits : isStaticArray, OriginalType;
            import miniorm.api : fromSqLiteDateTime;
            import miniorm.schema : fieldToCol;

            T ret;
            static string rr() {
                string[] res;
                foreach (i, a; fieldToCol!("", T)()) {
                    res ~= `{`;
                    if (a.columnType == "DATETIME") {
                        res ~= `{ ret.%1$s = fromSqLiteDateTime(e.peek!string(%2$d)); }`.format(a.identifier,
                                i);
                    } else {
                        res ~= q{alias ET = typeof(ret.%s);}.format(a.identifier);
                        res ~= q{static if (isStaticArray!ET)};
                        res ~= `
                            {
                                auto ubval = e[%2$d].as!(ubyte[]);
                                auto etval = cast(typeof(ET.init[]))ubval;
                                auto ln = min(ret.%1$s.length, etval.length);
                                ret.%1$s[0..ln] = etval[0..ln];
                            }
                            `.format(a.identifier, i);
                        res ~= q{else static if (is(ET == enum))};
                        res ~= format(q{ret.%1$s = cast(ET) e.peek!ET(%2$d).to!ET;},
                                a.identifier, i);
                        res ~= q{else};
                        res ~= format(q{ret.%1$s = e.peek!ET(%2$d);}, a.identifier, i);
                    }
                    res ~= `}`;
                }
                return res.join("\n");
            }

            mixin(rr());
            return ret;
        }

        return ResultRange2!(typeof(result))(stmt, result).map!qconv;
    }

    void run(T, Args...)(Delete!T v, auto ref Args args) {
        const sql = v.toSql.toString;
        if (isLog) {
            logger.trace(sql);
        }
        auto stmt = prepare(sql);
        executeCheck(stmt, sql, v.binds, args);
    }

    void run(T0, T1)(Insert!T0 v, T1[] arr...) if (!isInputRange!T1) {
        procInsert(v, arr);
    }

    void run(T, R)(Insert!T v, R rng) if (isInputRange!R) {
        procInsert(v, rng);
    }

    private void procInsert(T, R)(Insert!T q, R rng) {
        import std.algorithm : among;

        // generate code for binding values in a struct to a prepared
        // statement.
        // Expects an external variable "n" to exist that keeps track of the
        // index. This is requied when the binding is for multiple values.
        // Expects the statement to be named "stmt".
        // Expects the variable to read values from to be named "v".
        // Indexing start from 1 according to the sqlite manual.
        static string genBinding(T)(bool replace) {
            import miniorm.schema : fieldToCol;

            string s;
            foreach (i, v; fieldToCol!("", T)) {
                if (!replace && v.isPrimaryKey)
                    continue;
                if (v.columnType == "DATETIME")
                    s ~= "stmt.get.bind(n+1, v." ~ v.identifier ~ ".toUTC.toSqliteDateTime);";
                else
                    s ~= "stmt.get.bind(n+1, v." ~ v.identifier ~ ");";
                s ~= "++n;";
            }
            return s;
        }

        alias T = ElementType!R;

        const replace = q.query.opt == InsertOpt.InsertOrReplace;

        q = q.values(1);

        const sql = q.toSql.toString;

        auto stmt = prepare(sql);

        foreach (v; rng) {
            int n;
            if (replace) {
                mixin(genBinding!T(true));
            } else {
                mixin(genBinding!T(false));
            }
            if (isLog) {
                logger.trace(sql, " -> ", v);
            }
            stmt.get.execute();
            stmt.get.reset();
        }
    }
}

/** Wheter one aggregated insert or multiple should be generated.
 *
 * no:
 * ---
 * INSERT INTO foo ('v0') VALUES (?)
 * INSERT INTO foo ('v0') VALUES (?)
 * INSERT INTO foo ('v0') VALUES (?)
 * ---
 *
 * yes:
 * ---
 * INSERT INTO foo ('v0') VALUES (?) (?) (?)
 * ---
 */
enum AggregateInsert {
    no,
    yes
}

version (unittest) {
    import miniorm.schema;

    import std.conv : text, to;
    import std.range;
    import std.algorithm;
    import std.datetime;
    import std.array;
    import std.stdio;

    import unit_threaded.assertions;
}

@("shall operate on a database allocted in std.experimental.allocators without any errors")
unittest {
    struct One {
        ulong id;
        string text;
    }

    // TODO: fix this
    //import std.experimental.allocator;
    //import std.experimental.allocator.mallocator;
    //import std.experimental.allocator.building_blocks.scoped_allocator;
    //Microrm* db;
    //ScopedAllocator!Mallocator scalloc;
    //db = scalloc.make!Microrm(":memory:");
    //scope (exit) {
    //    db.close;
    //    scalloc.dispose(db);
    //}

    // TODO: replace the one below with the above code.
    auto db = Miniorm(":memory:");
    db.run(buildSchema!One);
    db.run(insert!One.insert, iota(0, 10).map!(i => One(i * 100, "hello" ~ text(i))));
    db.run(count!One).shouldEqual(10);

    auto ones = db.run(select!One).array;
    ones.length.shouldEqual(10);
    assert(ones.all!(a => a.id < 100));
    db.getUnderlyingDb.lastInsertRowid.shouldEqual(ones[$ - 1].id);

    db.run(delete_!One);
    db.run(count!One).shouldEqual(0);
    db.run(insertOrReplace!One, iota(0, 499).map!(i => One((i + 1) * 100, "hello" ~ text(i))));
    ones = db.run(select!One).array;
    ones.length.shouldEqual(499);
    assert(ones.all!(a => a.id >= 100));
    db.lastInsertRowid.shouldEqual(ones[$ - 1].id);
}

@("shall insert and extract datetime from the table")
unittest {
    import std.datetime : Clock;
    import core.thread : Thread;

    struct One {
        ulong id;
        SysTime time;
    }

    auto db = Miniorm(":memory:");
    db.run(buildSchema!One);

    const time = Clock.currTime;
    Thread.sleep(1.dur!"msecs");

    db.run(insert!One.insert, One(0, Clock.currTime));

    auto ones = db.run(select!One).array;
    ones.length.shouldEqual(1);
    ones[0].time.shouldBeGreaterThan(time);
}

unittest {
    struct One {
        ulong id;
        string text;
    }

    auto db = Miniorm(":memory:");
    db.run(buildSchema!One);

    db.run(count!One).shouldEqual(0);
    db.run(insert!One.insert, iota(0, 10).map!(i => One(i * 100, "hello" ~ text(i))));
    db.run(count!One).shouldEqual(10);

    auto ones = db.run(select!One).array;
    assert(ones.length == 10);
    assert(ones.all!(a => a.id < 100));
    assert(db.lastInsertRowid == ones[$ - 1].id);

    db.run(delete_!One);
    db.run(count!One).shouldEqual(0);

    import std.datetime;
    import std.conv : to;

    db.run(insertOrReplace!One, iota(0, 499).map!(i => One((i + 1) * 100, "hello" ~ text(i))));
    ones = db.run(select!One).array;
    assert(ones.length == 499);
    assert(ones.all!(a => a.id >= 100));
    assert(db.lastInsertRowid == ones[$ - 1].id);
}

@("shall convert the database type to the enum when retrieving via select")
unittest {
    static struct Foo {
        enum MyEnum : string {
            foo = "batman",
            bar = "robin",
        }

        ulong id;
        MyEnum enum_;
    }

    auto db = Miniorm(":memory:");
    db.run(buildSchema!Foo);

    db.run(insert!Foo.insert, Foo(0, Foo.MyEnum.bar));
    auto res = db.run(select!Foo).array;

    res.length.shouldEqual(1);
    res[0].enum_.shouldEqual(Foo.MyEnum.bar);
}

unittest {
    struct Limit {
        int min, max;
    }

    struct Limits {
        Limit volt, curr;
    }

    struct Settings {
        ulong id;
        Limits limits;
    }

    auto db = Miniorm(":memory:");
    db.run(buildSchema!Settings);
    assert(db.run(count!Settings) == 0);
    db.run(insertOrReplace!Settings, Settings(10, Limits(Limit(0, 12), Limit(-10, 10))));
    assert(db.run(count!Settings) == 1);

    db.run(insertOrReplace!Settings, Settings(10, Limits(Limit(0, 2), Limit(-3, 3))));
    db.run(insertOrReplace!Settings, Settings(11, Limits(Limit(0, 11), Limit(-11, 11))));
    db.run(insertOrReplace!Settings, Settings(12, Limits(Limit(0, 12), Limit(-12, 12))));

    assert(db.run(count!Settings) == 3);
    assert(db.run(count!Settings.where(`"limits.volt.max" = :nr`, Bind("nr")), 2) == 1);
    assert(db.run(count!Settings.where(`"limits.volt.max" > :nr`, Bind("nr")), 10) == 2);
    db.run(count!Settings.where(`"limits.volt.max" > :nr`, Bind("nr"))
            .and(`"limits.volt.max" < :topnr`, Bind("topnr")), 1, 12).shouldEqual(2);

    db.run(delete_!Settings.where(`"limits.volt.max" < :nr`, Bind("nr")), 10);
    assert(db.run(count!Settings) == 2);
}

unittest {
    struct Settings {
        ulong id;
        int[5] data;
    }

    auto db = Miniorm(":memory:");
    db.run(buildSchema!Settings);

    db.run(insert!Settings.insert, Settings(0, [1, 2, 3, 4, 5]));

    assert(db.run(count!Settings) == 1);
    auto s = db.run(select!Settings).front;
    assert(s.data == [1, 2, 3, 4, 5]);
}

SysTime fromSqLiteDateTime(string raw_dt) {
    import std.datetime : DateTime, UTC, Clock;
    import std.format : formattedRead;

    try {
        int year, month, day, hour, minute, second, msecs;
        formattedRead(raw_dt, "%s-%s-%s %s:%s:%s.%s", year, month, day, hour,
                minute, second, msecs);
        auto dt = DateTime(year, month, day, hour, minute, second);
        return SysTime(dt, msecs.dur!"msecs", UTC());
    } catch (Exception e) {
        logger.trace(e.msg);
        return Clock.currTime(UTC());
    }
}

/// To ensure a consistency the time is always converted to UTC.
string toSqliteDateTime(SysTime ts_) {
    import std.format;

    auto ts = ts_.toUTC;
    return format("%04s-%02s-%02s %02s:%02s:%02s.%s", ts.year,
            cast(ushort) ts.month, ts.day, ts.hour, ts.minute, ts.second,
            ts.fracSecs.total!"msecs");
}

class SpinSqlTimeout : Exception {
    this(string msg, string file = __FILE__, int line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/** Execute an SQL query until it succeeds.
 *
 * Note: If there are any errors in the query it will go into an infinite loop.
 */
auto spinSql(alias query, alias logFn = logger.warning)(Duration timeout, Duration minTime = 50.dur!"msecs",
        Duration maxTime = 150.dur!"msecs", const string file = __FILE__, const size_t line = __LINE__) {
    import core.thread : Thread;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    import std.exception : collectException;
    import std.format : format;
    import std.random : uniform;

    const sw = StopWatch(AutoStart.yes);
    const location = format!" [%s:%s]"(file, line);

    while (sw.peek < timeout) {
        try {
            return query();
        } catch (Exception e) {
            logFn(e.msg, location).collectException;
            // even though the database have a builtin sleep it still result in too much spam.
            () @trusted {
                Thread.sleep(uniform(minTime.total!"msecs", maxTime.total!"msecs").dur!"msecs");
            }();
        }
    }

    throw new SpinSqlTimeout(null);
}

auto spinSql(alias query, alias logFn = logger.warning)(const string file = __FILE__,
        const size_t line = __LINE__) nothrow {
    while (true) {
        try {
            return spinSql!(query, logFn)(Duration.max, 50.dur!"msecs",
                    150.dur!"msecs", file, line);
        } catch (Exception e) {
        }
    }
}

/// RAII handling of a transaction.
struct Transaction {
    Database db;

    // can only do a rollback/commit if it has been constructed and thus
    // executed begin.
    enum State {
        none,
        rollback,
        done,
    }

    State st;

    this(Miniorm db) {
        this(db.db);
    }

    this(Database db) {
        this.db = db;
        spinSql!(() { db.begin; });
        st = State.rollback;
    }

    ~this() {
        scope (exit)
            st = State.done;
        if (st == State.rollback) {
            db.rollback;
        }
    }

    void commit() {
        db.commit;
        st = State.done;
    }

    void rollback() {
        scope (exit)
            st = State.done;
        if (st == State.rollback) {
            db.rollback;
        }
    }
}

/// A prepared statement is lent to the user. The refcnt takes care of
/// resetting the statement when the user is done with it.
struct RefCntStatement {
    import std.exception : collectException;
    import std.typecons : RefCounted, RefCountedAutoInitialize, refCounted;

    static struct Payload {
        LentCntStatement* stmt;

        this(LentCntStatement* stmt) {
            this.stmt = stmt;
            stmt.count++;
        }

        ~this() nothrow {
            if (stmt is null)
                return;

            try {
                (*stmt).stmt.clearBindings;
                (*stmt).stmt.reset;
            } catch (Exception e) {
            }
            stmt.count--;
            stmt = null;
        }
    }

    RefCounted!(Payload, RefCountedAutoInitialize.no) rc;

    this(ref LentCntStatement stmt) @trusted {
        rc = Payload(&stmt);
    }

    ref Statement get() {
        return rc.refCountedPayload.stmt.stmt;
    }
}

struct ResultRange2(T) {
    RefCntStatement stmt;
    T result;

    auto front() {
        assert(!empty, "Can't get front of an empty range");
        return result.front;
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");
        result.popFront;
    }

    bool empty() {
        return result.empty;
    }
}

/// It is lent to a user and thus can't be finalized if the counter > 0.
private struct LentCntStatement {
    Statement stmt;
    long count;
}

@("shall remove all statements that are not lent to a user when the cache is full")
unittest {
    struct Settings {
        ulong id;
    }

    auto db = Miniorm(":memory:");
    db.run(buildSchema!Settings);
    db.prepareCacheSize = 1;

    { // reuse statement
        auto s0 = db.prepare("select * from Settings");
        auto s1 = db.prepare("select * from Settings");

        db.cachedStmt.length.shouldEqual(1);
        db.cachedStmt["select * from Settings"].count.shouldEqual(2);
    }
    db.cachedStmt.length.shouldEqual(1);
    db.cachedStmt["select * from Settings"].count.shouldEqual(0);

    { // a lent statement is not removed when the cache is full
        auto s0 = db.prepare("select * from Settings");
        auto s1 = db.prepare("select id from Settings");

        db.cachedStmt.length.shouldEqual(2);
        ("select * from Settings" in db.cachedStmt).shouldBeTrue;
        ("select id from Settings" in db.cachedStmt).shouldBeTrue;
    }
    db.cachedStmt.length.shouldEqual(2);

    { // statements not lent to a user is removed when the cache is full
        auto s0 = db.prepare("select * from Settings");

        db.cachedStmt.length.shouldEqual(1);
        ("select * from Settings" in db.cachedStmt).shouldBeTrue;
        ("select id from Settings" in db.cachedStmt).shouldBeFalse;
    }
}
