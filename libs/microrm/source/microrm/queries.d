module microrm.queries;

import std.algorithm : joiner, map;
import std.exception : enforce;
import std.string : join;

import d2sqlite3;

import microrm.schema : tableName, IDNAME, fieldToCol, fieldToCol, ColumnName;
import microrm.exception;

debug (microrm) import std.stdio : stderr;

version (unittest) {
    import unit_threaded.assertions;
}

enum BASEQUERYLENGTH = 512;

struct Select(T, BUF) {
    import std.range : InputRange;

    mixin baseQueryData!("SELECT * FROM %s");
    mixin whereCondition;

    private ref orderBy(string[] fields, string orderType) {
        assert(orderType == "ASC" || orderType == "DESC");
        query.put(" ORDER BY ");
        query.put(fields.joiner(", "));
        query.put(" ");
        query.put(orderType);
        return this;
    }

    ref ascOrderBy(string[] fields...) {
        return orderBy(fields, "ASC");
    }

    ref descOrderBy(string[] fields...) {
        return orderBy(fields, "DESC");
    }

    auto run() @property {
        import std.range : inputRangeObject;
        import std.algorithm : map;

        enforce(db, "database is null");

        query.put(';');
        auto q = query.data.idup;
        debug (microrm)
            stderr.writeln(q);
        auto result = (*db).executeCheck(q);

        static T qconv(typeof(result.front) e) {
            T ret;
            static string rr() {
                string[] res;
                res ~= "import std.traits : isStaticArray, OriginalType;";
                foreach (i, a; fieldToCol!("", T)()) {
                    res ~= `{`;
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
                    res ~= `}`;
                }
                return res.join("\n");
            }

            mixin(rr());
            return ret;
        }

        return result.map!qconv;
    }
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        ulong ts;
    }

    import std.array : Appender;

    Appender!(char[]) buf;

    auto test = Select!(Foo, typeof(buf))(null, &buf);
    test.where("text =", "privet").and("ts >", 123);
    assert(test.query.data == "SELECT * FROM Foo WHERE text = 'privet' AND ts > '123'");
}

@("shall be possible to have a member of enum type")
unittest {
    static struct Foo {
        enum MyEnum : string {
            foo = "batman",
            bar = "robin",
        }

        ulong id;
        MyEnum enum_;
    }

    import std.array : Appender;

    Appender!(char[]) buf;

    auto test = Select!(Foo, typeof(buf))(null, &buf);
    test.where("enum_ =", "robin");
    test.query.data.shouldEqual("SELECT * FROM Foo WHERE enum_ = 'robin'");
}

void buildInsertOrReplace(T, W)(ref W buf, bool replace, size_t valCount = 1) {
    if (!replace)
        buf.put("INSERT INTO ");
    else
        buf.put("INSERT OR REPLACE INTO ");
    buf.put(tableName!T);
    buf.put(" (");

    enum fields = fieldToCol!("", T)();

    foreach (i, f; fields) {
        if (f.isPrimaryKey && !replace)
            continue;
        buf.put(f.quoteColumnName);
        if (i + 1 != fields.length)
            buf.put(",");
    }
    buf.put(") VALUES (");

    foreach (n; 0 .. valCount) {
        foreach (i, f; fields) {
            if (f.isPrimaryKey && !replace)
                continue;
            buf.put("?");
            if (i + 1 != fields.length)
                buf.put(",");
        }
        if (n + 1 != valCount)
            buf.put("),(");
    }
    buf.put(");");
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        float val;
        ulong ts;

        @ColumnName("version")
        string version_;
    }

    import std.array : appender;

    auto buf = appender!(char[]);

    buf.buildInsertOrReplace!Foo(true);
    auto q = buf.data;
    q.shouldEqual(
            "INSERT OR REPLACE INTO Foo "
            ~ "('id','text','val','ts','version') VALUES " ~ "(?,?,?,?,?);");
    buf.clear();
    buf.buildInsertOrReplace!Foo(false);
    q = buf.data;
    q.shouldEqual("INSERT INTO Foo " ~ "('text','val','ts','version') VALUES " ~ "(?,?,?,?);");
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        float val;
        ulong ts;
    }

    static struct Bar {
        ulong id;
        float value;
        Foo foo;
    }

    import std.array : appender;

    auto buf = appender!(char[]);

    buf.buildInsertOrReplace!Bar(true);
    auto q = buf.data;
    q.shouldEqual(
            "INSERT OR REPLACE INTO Bar ('id','value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?,?);");
    buf.clear();
    buf.buildInsertOrReplace!Bar(false);
    q = buf.data;
    q.shouldEqual(
            "INSERT INTO Bar ('value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?);");
    buf.clear();
    buf.buildInsertOrReplace!Bar(false, 3);
    q = buf.data;
    q.shouldEqual(
            "INSERT INTO Bar ('value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?),(?,?,?,?,?),(?,?,?,?,?);");
}

unittest {
    struct Foo {
        string text;
        float val;
        ulong ts;
    }

    struct Bar {
        float v;
        Foo foo;
    }

    struct Baz {
        ulong id;
        float v;
        Bar xyz;
        float w;
    }

    import std.array : appender;

    auto buf = appender!(char[]);

    buf.buildInsertOrReplace!Baz(true);
    auto q = buf.data;
    q.shouldEqual("INSERT OR REPLACE INTO Baz "
            ~ "('id','v','xyz.v','xyz.foo.text','xyz.foo.val','xyz.foo.ts','w') VALUES (?,?,?,?,"
            ~ "?,?,?);");
}

struct Delete(T, BUF) {
    mixin baseQueryData!("DELETE FROM %s");
    mixin whereCondition;

    auto run() @property {
        enforce(db, "database is null");

        query.put(';');
        auto q = query.data.idup;
        debug (microrm)
            stderr.writeln(q);
        return (*db).executeCheck(q);
    }
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        ulong ts;
    }

    import std.array : Appender;

    Appender!(char[]) buf;

    auto test = Delete!(Foo, typeof(buf))(null, &buf);
    test.where("text =", "privet").and("ts >", 123);
    test.query.data.shouldEqual("DELETE FROM Foo WHERE text = 'privet' AND ts > '123'");
}

struct Count(T, BUF) {
    mixin baseQueryData!("SELECT Count(*) FROM %s");
    mixin whereCondition;

    size_t run() @property {
        enforce(db, "database is null");
        auto q = query.data.idup;
        debug (microrm)
            stderr.writeln(q);
        return (*db).executeCheck(q).front.front.as!size_t;
    }
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        ulong ts;
    }

    import std.array : Appender;

    Appender!(char[]) buf;

    auto test = Count!(Foo, typeof(buf))(null, &buf);
    test.where("text =", "privet").and("ts >", 123);
    test.query.data.shouldEqual("SELECT Count(*) FROM Foo WHERE text = 'privet' AND ts > '123'");
}

private:

mixin template whereCondition() {
    import std.format : formattedWrite;
    import std.conv : text;
    import std.range : isOutputRange;

    static assert(isOutputRange!(typeof(this.query), char));

    ref where(V)(string field, V val) {
        query.put(" WHERE ");
        query.put(field);
        query.put(" '");
        version (LDC)
            query.put(text(val));
        else
            query.formattedWrite("%s", val);
        query.put("'");
        return this;
    }

    ref whereQ(string field, string cmd) {
        query.put(" WHERE ");
        query.put(field);
        query.put(" ");
        query.put(cmd);
        return this;
    }

    ref and(V)(string field, V val) {
        query.put(" AND ");
        query.put(field);
        query.put(" '");
        version (LDC)
            query.put(text(val));
        else
            query.formattedWrite("%s", val);
        query.put("'");
        return this;
    }

    ref andQ(string field, string cmd) {
        query.put(" AND ");
        query.put(field);
        query.put(" ");
        query.put(cmd);
        return this;
    }

    ref limit(int limit) {
        query.put(" LIMIT '");
        version (LDC)
            query.put(text(limit));
        else
            query.formattedWrite("%s", limit);
        query.put("'");
        return this;
    }
}

mixin template baseQueryData(string SQLTempl) {
    import std.array : Appender, appender;
    import std.format : formattedWrite, format;

    enum initialSQL = format(SQLTempl, tableName!T);

    alias Buffer = BUF;

    Database* db;
    Buffer* buf;

    @disable this();

    private ref Buffer query() @property {
        return (*buf);
    }

    this(Database* db, Buffer* buf) {
        this.db = db;
        this.buf = buf;
        query.put(initialSQL);
    }

    void reset() {
        query.clear();
        query.put(initialSQL);
    }

    /// Reset the query to table `name`.
    ref setTable(string name) {
        query.clear;
        query.put(format(SQLTempl, name));
        return this;
    }
}
