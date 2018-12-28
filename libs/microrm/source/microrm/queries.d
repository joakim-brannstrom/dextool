module microrm.queries;

import std.exception : enforce;
import std.algorithm : joiner;
import std.string : join;

import d2sqlite3;

import microrm.schema : tableName, IDNAME, fieldNames;
import microrm.exception;

debug (microrm) import std.stdio : stderr;

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
            enum names = fieldNames!("", T)();
            T ret;
            static string rr() {
                string[] res;
                res ~= "import std.traits : isStaticArray;";
                foreach (i, a; fieldNames!("", T)()) {
                    res ~= `{`;
                    res ~= q{alias ET = typeof(ret.%s);}.format(a[1 .. $ - 1]);
                    res ~= q{static if (isStaticArray!ET)};
                    res ~= `
                        {
                            import std.algorithm : min;
                            auto ubval = e[%2$d].as!(ubyte[]);
                            auto etval = cast(typeof(ET.init[]))ubval;
                            auto ln = min(ret.%1$s.length, etval.length);
                            ret.%1$s[0..ln] = etval[0..ln];
                        }
                        `.format(a[1 .. $ - 1], i);
                    res ~= q{else};
                    res ~= format(q{ret.%1$s = e.peek!ET(%2$d);}, a[1 .. $ - 1], i);
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

void buildInsertOrReplace(T, W)(ref W buf, bool replace, size_t valCount = 1) {
    if (!replace)
        buf.put("INSERT INTO ");
    else
        buf.put("INSERT OR REPLACE INTO ");
    buf.put(tableName!T);
    buf.put(" (");

    bool isInsertId = true;

    auto tt = T.init;
    foreach (i, f; tt.tupleof) {
        alias F = typeof(f);
        enum name = __traits(identifier, tt.tupleof[i]);

        static if (is(F == struct))
            enum tmp = fieldNames!(name, F)().join(",");
        else {
            if (name == IDNAME && !replace)
                continue;
            enum tmp = "'" ~ name ~ "'";
        }

        buf.put(tmp);
        static if (i + 1 != tt.tupleof.length)
            buf.put(",");
    }
    buf.put(") VALUES (");

    foreach (n; 0 .. valCount) {
        foreach (i, f; tt.tupleof) {
            enum name = __traits(identifier, tt.tupleof[i]);
            alias F = typeof(f);
            static if (is(F == struct))
                buf.fmtValues!F;
            else {
                if (name == IDNAME && !replace)
                    continue;
                buf.put("?");
            }
            static if (i + 1 != tt.tupleof.length)
                buf.put(",");
        }
        if (n + 1 != valCount)
            buf.put("),(");
    }
    buf.put(");");
}

void fmtValues(T, W)(ref W buf) {
    auto tt = T.init;
    foreach (i, f; tt.tupleof) {
        alias F = typeof(f);
        static if (is(F == struct))
            buf.fmtValues!F;
        else
            buf.put("?");
        static if (i + 1 != tt.tupleof.length)
            buf.put(",");
    }
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        float val;
        ulong ts;
    }

    import std.array : appender;

    auto buf = appender!(char[]);

    buf.buildInsertOrReplace!Foo(true);
    auto q = buf.data;
    assert(q == "INSERT OR REPLACE INTO Foo " ~ "('id','text','val','ts') VALUES " ~ "(?,?,?,?);");
    buf.clear();
    buf.buildInsertOrReplace!Foo(false);
    q = buf.data;
    assert(q == "INSERT INTO Foo " ~ "('text','val','ts') VALUES " ~ "(?,?,?);");
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
    assert(q == "INSERT OR REPLACE INTO Bar "
            ~ "('id','value','foo.id','foo.text','foo.val','foo.ts') VALUES " ~ "(?,?,?,?,?,?);");
    buf.clear();
    buf.buildInsertOrReplace!Bar(false);
    q = buf.data;
    assert(q == "INSERT INTO Bar "
            ~ "('value','foo.id','foo.text','foo.val','foo.ts') VALUES " ~ "(?,?,?,?,?);");
    buf.clear();
    buf.buildInsertOrReplace!Bar(false, 3);
    q = buf.data;
    assert(q == "INSERT INTO Bar " ~ "('value','foo.id','foo.text','foo.val','foo.ts') VALUES "
            ~ "(?,?,?,?,?),(?,?,?,?,?),(?,?,?,?,?);");
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
    assert(q == "INSERT OR REPLACE INTO Baz " ~ "('id','v','xyz.v',"
            ~ "'xyz.foo.text','xyz.foo.val','xyz.foo.ts','w') VALUES " ~ "(?,?,?,?," ~ "?,?,?);");
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
    assert(test.query.data == "DELETE FROM Foo WHERE text = 'privet' AND ts > '123'");
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
    assert(test.query.data == "SELECT Count(*) FROM Foo WHERE text = 'privet' AND ts > '123'");
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
}
