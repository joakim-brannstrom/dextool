/**
Copyright: Copyright (c) 2017, Oleg Butko. All rights reserved.
Copyright: Copyright (c) 2018-2019, Joakim Brännström. All rights reserved.
License: MIT
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
Author: Oleg Butko (deviator)
*/
module miniorm.api;

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
    private Statement[string] cachedStmt;
    /// True means that all queries are logged.
    private bool log_;

    ///
    Database db;
    alias getUnderlyingDb this;

    ref Database getUnderlyingDb() {
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

    /// Toggle logging.
    void log(bool v) {
        this.log_ = v;
    }

    /// Returns: True if logging is activated
    private bool isLog() {
        return log_;
    }

    private void cleanupCache() {
        foreach (ref s; cachedStmt.byValue)
            s.finalize;
        cachedStmt = null;
    }

    void opAssign(ref typeof(this) rhs) {
        cleanupCache;
        db = rhs.db;
    }

    void run(string sql, bool delegate(ResultRange) dg = null) {
        if (isLog)
            logger.trace(sql);
        db.run(sql, dg);
    }

    void close() {
        cleanupCache;
        db.close();
    }

    size_t run(T)(Count!T v) {
        const sql = v.toSql.toString;
        if (isLog)
            logger.trace(sql);
        return db.executeCheck(sql).front.front.as!size_t;
    }

    auto run(T)(Select!T v) {
        import std.algorithm : map;
        import std.format : format;
        import std.range : inputRangeObject;

        const sql = v.toSql.toString;
        if (isLog)
            logger.trace(sql);

        auto result = db.executeCheck(sql);

        static T qconv(typeof(result.front) e) {
            import miniorm.schema : fieldToCol;

            T ret;
            static string rr() {
                string[] res;
                res ~= "import std.traits : isStaticArray, OriginalType;";
                res ~= "import miniorm.api : fromSqLiteDateTime;";
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
                                import std.algorithm : min;
                                auto ubval = e[%2$d].as!(ubyte[]);
                                auto etval = cast(typeof(ET.init[]))ubval;
                                auto ln = min(ret.%1$s.length, etval.length);
                                ret.%1$s[0..ln] = etval[0..ln];
                            }
                            `.format(a.identifier, i);
                        res ~= q{else static if (is(ET == enum))};
                        res ~= format(q{ret.%1$s = cast(ET) e.peek!ET(%2$d);}, a.identifier, i);
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

        return result.map!qconv;
    }

    void run(T)(Delete!T v) {
        const sql = v.toSql.toString;
        if (isLog)
            logger.trace(sql);
        db.run(sql);
    }

    void run(AggregateInsert all = AggregateInsert.no, T0, T1)(Insert!T0 v, T1[] arr...)
            if (!isInputRange!T1) {
        procInsert!all(v, arr);
    }

    void run(AggregateInsert all = AggregateInsert.no, T, R)(Insert!T v, R rng)
            if (isInputRange!R) {
        procInsert!all(v, rng);
    }

    private void procInsert(AggregateInsert all = AggregateInsert.no, T, R)(Insert!T q, R rng)
            if ((all && hasLength!R) || !all) {
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
                    s ~= "stmt.bind(n+1, v." ~ v.identifier ~ ".toUTC.toSqliteDateTime);";
                else
                    s ~= "stmt.bind(n+1, v." ~ v.identifier ~ ");";
                s ~= "++n;";
            }
            return s;
        }

        alias T = ElementType!R;

        const replace = q.query.opt == InsertOpt.InsertOrReplace;

        static if (all == AggregateInsert.yes)
            q = q.values(rng.length);
        else
            q = q.values(1);

        const sql = q.toSql.toString;

        if (sql !in cachedStmt)
            cachedStmt[sql] = db.prepare(sql);
        auto stmt = cachedStmt[sql];

        static if (all == AggregateInsert.yes) {
            int n;
            foreach (v; rng) {
                if (replace) {
                    mixin(genBinding!T(true));
                } else {
                    mixin(genBinding!T(false));
                }
            }
            if (isLog)
                logger.trace(sql, " -> ", rng);
            stmt.execute();
            stmt.reset();
        } else {
            foreach (v; rng) {
                int n;
                if (replace) {
                    mixin(genBinding!T(true));
                } else {
                    mixin(genBinding!T(false));
                }
                if (isLog)
                    logger.trace(sql, " -> ", v);
                stmt.execute();
                stmt.reset();
            }
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

    import std.experimental.allocator;
    import std.experimental.allocator.mallocator;
    import std.experimental.allocator.building_blocks.scoped_allocator;

    // TODO: fix this
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
    import core.time : dur;

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
    db.run!(AggregateInsert.yes)(insert!One.insert, iota(0, 10)
            .map!(i => One(i * 100, "hello" ~ text(i))));
    db.run(count!One).shouldEqual(10);

    auto ones = db.run(select!One).array;
    assert(ones.length == 10);
    assert(ones.all!(a => a.id < 100));
    assert(db.lastInsertRowid == ones[$ - 1].id);

    db.run(delete_!One);
    db.run(count!One).shouldEqual(0);

    import std.datetime;
    import std.conv : to;

    db.run!(AggregateInsert.yes)(insertOrReplace!One, iota(0, 499)
            .map!(i => One((i + 1) * 100, "hello" ~ text(i))));
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
    assert(db.run(count!Settings.where(`"limits.volt.max" = 2`)) == 1);
    assert(db.run(count!Settings.where(`"limits.volt.max" > 10`)) == 2);
    db.run(delete_!Settings.where(`"limits.volt.max" < 10`));
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
    import core.time : dur;
    import std.datetime : DateTime, UTC;
    import std.format : formattedRead;

    int year, month, day, hour, minute, second, msecs;
    formattedRead(raw_dt, "%s-%s-%s %s:%s:%s.%s", year, month, day, hour, minute, second, msecs);
    auto dt = DateTime(year, month, day, hour, minute, second);

    return SysTime(dt, msecs.dur!"msecs", UTC());
}

string toSqliteDateTime(SysTime ts) {
    import std.format;

    return format("%04s-%02s-%02s %02s:%02s:%02s.%s", ts.year,
            cast(ushort) ts.month, ts.day, ts.hour, ts.minute, ts.second,
            ts.fracSecs.total!"msecs");
}

class SpinSqlTimeout : Exception {
    this() {
        super(null);
    }
}

/** Execute an SQL query until it succeeds.
 *
 * Note: If there are any errors in the query it will go into an infinite loop.
 */
auto spinSql(alias query, alias logFn = logger.warning)(Duration timeout = Duration.max) {
    import core.thread : Thread;
    import core.time : dur;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    import std.exception : collectException;
    import std.random : uniform;

    const sw = StopWatch(AutoStart.yes);

    while (sw.peek < timeout) {
        try {
            return query();
        } catch (Exception e) {
            logFn(e.msg).collectException;
            // even though the database have a builtin sleep it still result in too much spam.
            Thread.sleep(uniform(50, 150).dur!"msecs");
        }
    }

    throw new SpinSqlTimeout();
}
