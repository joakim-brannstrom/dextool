///
module microrm.api;

import std.array : Appender;
import std.range;

import microrm.queries;
import microrm.util;
import microrm.exception;

import d2sqlite3;

debug (microrm) import std.stdio : stderr;

///
struct Microrm {
    private Statement[string] cachedStmt;
    private Appender!(char[]) buf;

    ///
    Database db;
    alias getUnderlyingDb this;

    ref Database getUnderlyingDb() {
        return db;
    }

    alias getUnderlyingDb this;

    ///
    this(Database db, size_t queryBufferInitReserve = 512) {
        this.db = db;
        this.buf.reserve(queryBufferInitReserve);
    }

    ///
    this(string path, int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            size_t queryBufferInitReserve = 512) {
        this(Database(path, flags), queryBufferInitReserve);
    }

    ~this() {
        cleanupCache;
    }

    private void cleanupCache() {
        foreach (ref s; cachedStmt.byValue)
            s.finalize;
        cachedStmt = null;
    }

    void opAssign(ref typeof(this) rhs) {
        cleanupCache;
        db = rhs.db;
        buf.reserve(rhs.buf.data.length);
    }

    void run(string script, bool delegate(ResultRange) dg = null) {
        db.run(script, dg);
    }

    void close() {
        cleanupCache;
        db.close();
    }

    ///
    auto select(T)() {
        buf.clear();
        return Select!(T, typeof(buf))(&db, &buf);
    }

    ///
    auto count(T)() {
        buf.clear();
        return Count!(T, typeof(buf))(&db, &buf);
    }

    ///
    void insert(bool all = false, T)(T[] arr...) if (!isInputRange!T) {
        procInsert!all(false, arr);
    }
    ///
    void insertOrReplace(bool all = false, T)(T[] arr...) if (!isInputRange!T) {
        procInsert!all(true, arr);
    }

    ///
    void insert(bool all = false, R)(R rng)
            if (isInputRange!R && ((all && hasLength!R) || !all)) {
        procInsert!all(false, rng);
    }
    ///
    void insertOrReplace(bool all = false, R)(R rng)
            if (isInputRange!R && ((all && hasLength!R) || !all)) {
        procInsert!all(true, rng);
    }

    private auto procInsert(bool all = false, R)(bool replace, R rng)
            if ((all && hasLength!R) || !all) {
        buf.clear;
        alias T = ElementType!R;
        static if (all)
            buf.buildInsertOrReplace!T(replace, rng.length);
        else
            buf.buildInsertOrReplace!T(replace);

        auto sql = buf.data.idup;

        debug (microrm)
            stderr.writeln(sql);

        if (sql !in cachedStmt)
            cachedStmt[sql] = db.prepare(sql);
        auto stmt = cachedStmt[sql];

        int n;
        static if (all) {
            foreach (v; rng)
                bindStruct(stmt, v, replace, n);
            stmt.execute();
            stmt.reset();
        } else
            foreach (v; rng) {
                n = 0;
                bindStruct(stmt, v, replace, n);
                stmt.execute();
                stmt.reset();
            }

        return true;
    }

    ///
    auto del(T)() {
        buf.clear();
        return Delete!(T, typeof(buf))(&db, &buf);
    }

    private static int bindStruct(T)(ref Statement stmt, T v, bool replace, ref int n) {
        foreach (i, f; v.tupleof) {
            enum name = __traits(identifier, v.tupleof[i]);
            alias F = typeof(f);
            static if (is(F == struct))
                bindStruct(stmt, f, replace, n);
            else {
                if (name == IDNAME && !replace)
                    continue;
                stmt.bind(n + 1, f);
                n++;
            }
        }
        return n;
    }
}

version (unittest) {
    import microrm.schema;

    import std.conv : text, to;
    import std.range;
    import std.algorithm;
    import std.datetime;
    import std.array;
    import std.stdio;
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
    auto db = Microrm(":memory:");
    db.run(buildSchema!One);

    assert(db.count!One.run == 0);
    db.insert(iota(0, 10).map!(i => One(i * 100, "hello" ~ text(i))));
    assert(db.count!One.run == 10);

    auto ones = db.select!One.run.array;
    assert(ones.length == 10);
    assert(ones.all!(a => a.id < 100));
    assert(db.getUnderlyingDb.lastInsertRowid == ones[$ - 1].id);
    db.del!One.run;
    assert(db.count!One.run == 0);
    db.insertOrReplace(iota(0, 499).map!(i => One((i + 1) * 100, "hello" ~ text(i))));
    assert(ones.length == 10);
    ones = db.select!One.run.array;
    assert(ones.length == 499);
    assert(ones.all!(a => a.id >= 100));
    assert(db.lastInsertRowid == ones[$ - 1].id);
}

unittest {
    struct One {
        ulong id;
        string text;
    }

    auto db = Microrm(":memory:");
    db.run(buildSchema!One);

    assert(db.count!One.run == 0);
    db.insert!true(iota(0, 10).map!(i => One(i * 100, "hello" ~ text(i))));
    assert(db.count!One.run == 10);

    auto ones = db.select!One.run.array;
    assert(ones.length == 10);
    assert(ones.all!(a => a.id < 100));
    assert(db.lastInsertRowid == ones[$ - 1].id);
    db.del!One.run;
    assert(db.count!One.run == 0);
    import std.datetime;
    import std.conv : to;

    db.insertOrReplace!true(iota(0, 499).map!(i => One((i + 1) * 100, "hello" ~ text(i))));
    assert(ones.length == 10);
    ones = db.select!One.run.array;
    assert(ones.length == 499);
    assert(ones.all!(a => a.id >= 100));
    assert(db.lastInsertRowid == ones[$ - 1].id);
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

    auto db = Microrm(":memory:");
    db.run(buildSchema!Settings);
    assert(db.count!Settings.run == 0);
    db.insertOrReplace(Settings(10, Limits(Limit(0, 12), Limit(-10, 10))));
    assert(db.count!Settings.run == 1);

    db.insertOrReplace(Settings(10, Limits(Limit(0, 2), Limit(-3, 3))));
    db.insertOrReplace(Settings(11, Limits(Limit(0, 11), Limit(-11, 11))));
    db.insertOrReplace(Settings(12, Limits(Limit(0, 12), Limit(-12, 12))));

    assert(db.count!Settings.run == 3);
    assert(db.count!Settings.where(`"limits.volt.max" = `, 2).run == 1);
    assert(db.count!Settings.where(`"limits.volt.max" > `, 10).run == 2);
    db.del!Settings.where(`"limits.volt.max" < `, 10).run;
    assert(db.count!Settings.run == 2);
}

unittest {
    struct Settings {
        ulong id;
        int[5] data;
    }

    auto db = Microrm(":memory:");
    db.run(buildSchema!Settings);

    db.insert(Settings(0, [1, 2, 3, 4, 5]));

    assert(db.count!Settings.run == 1);
    auto s = db.select!Settings.run.front;
    assert(s.data == [1, 2, 3, 4, 5]);
}
