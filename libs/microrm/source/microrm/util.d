module microrm.util;

import std.traits;
import std.format : format, formattedWrite;

enum IDNAME = "id";
enum SEPARATOR = ".";

string tableName(T)() {
    return T.stringof;
}

string[] fieldToCol(string name, T)(string prefix = "") {
    static if (name == IDNAME)
        return ["'" ~ IDNAME ~ "' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL"];
    else static if (is(T == struct)) {
        T t;
        string[] ret;
        foreach (i, f; t.tupleof) {
            enum fname = __traits(identifier, t.tupleof[i]);
            alias F = typeof(f);
            auto np = prefix ~ (name.length ? name ~ SEPARATOR : "");
            ret ~= fieldToCol!(fname, F)(np);
        }
        return ret;
    } else {
        enum NOTNULL = " NOT NULL";
        string type, param;
        static if (isFloatingPoint!T)
            type = "REAL";
        else static if (isNumeric!T || is(T == bool)) {
            type = "INTEGER";
            param = NOTNULL;
        } else static if (isSomeString!T)
            type = "TEXT";
        else static if (isArray!T)
            type = "BLOB";
        else
            static assert(0, "unsupported type: " ~ T.stringof);

        return [format("'%s%s' %s%s", prefix, name, type, param)];
    }
}

unittest {
    struct Baz {
        string a, b;
    }

    struct Foo {
        float xx;
        string yy;
        Baz baz;
        int zz;
    }

    struct Bar {
        ulong id;
        float abc;
        Foo foo;
        string baz;
        ubyte[] data;
    }

    assert(fieldToCol!("", Bar)() == ["'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL",
            "'abc' REAL", "'foo.xx' REAL", "'foo.yy' TEXT",
            "'foo.baz.a' TEXT", "'foo.baz.b' TEXT",
            "'foo.zz' INTEGER NOT NULL", "'baz' TEXT", "'data' BLOB"]);
}

void valueToCol(T, Writer)(ref Writer w, T x) {
    void fmtwrt(string fmt, T val) {
        // LDC, WTF? https://github.com/ldc-developers/ldc/issues/2355
        version (LDC)
            w.put(format(fmt, val));
        else
            w.formattedWrite(fmt, val);
    }

    static if (is(T == struct)) {
        foreach (i, v; x.tupleof) {
            valueToCol(w, v);
            static if (i + 1 != x.tupleof.length)
                w.put(",");
        }
    } else static if (is(T == bool))
        fmtwrt("%d", cast(int) x);
    else static if (isFloatingPoint!T) {
        if (x == x)
            fmtwrt("%e", x);
        else
            w.put("null");
    } else static if (isNumeric!T)
        fmtwrt("%d", x);
    else static if (isSomeString!T) {
        w.put('\'');
        w.put(x);
        w.put('\'');
    } else static if (isDynamicArray!T) {
        if (x.length == 0)
            w.put("null");
        else {
            static if (is(T == ubyte[]))
                auto dd = x;
            else
                auto dd = cast(ubyte[])(cast(void[]) x);
            fmtwrt("x'%-(%02x%)'", dd);
        }
    } else
        static assert(0, "unsupported type: " ~ T.stringof);
}

unittest {
    import std.array : Appender;

    Appender!(char[]) buf;
    valueToCol(buf, 3);
    assert(buf.data == "3");
    buf.clear;
    valueToCol(buf, "hello");
    assert(buf.data == "'hello'");
    buf.clear;
}

unittest {
    struct Foo {
        int xx;
        string yy;
    }

    struct Bar {
        ulong id;
        int abc;
        string baz;
        Foo foo;
    }

    Bar val = {id:
    12, abc : 32, baz : "hello", foo : {xx:
    45, yy : "ok"}};

    import std.array : Appender;

    Appender!(char[]) buf;
    valueToCol(buf, val);
    assert(buf.data == "12,32,'hello',45,'ok'");
}

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

string[] fieldNames(string name, T)(string prefix = "") {
    static if (is(T == struct)) {
        T t;
        string[] ret;
        foreach (i, f; t.tupleof) {
            enum fname = __traits(identifier, t.tupleof[i]);
            alias F = typeof(f);
            auto np = prefix ~ (name.length ? name ~ SEPARATOR : "");
            ret ~= fieldNames!(fname, F)(np);
        }
        return ret;
    } else
        return ["'" ~ prefix ~ name ~ "'"];
}

unittest {
    struct Foo {
        ulong id;
        float xx;
        string yy;
    }

    struct Bar {
        ulong id;
        float abc;
        Foo foo;
        string baz;
    }

    assert(fieldNames!("", Bar) == ["'id'", "'abc'", "'foo.id'", "'foo.xx'", "'foo.yy'", "'baz'"]);
}
