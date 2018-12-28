module microrm.schema;

/// UDA controlling the name of the table.
struct TableName {
    string value;
}

/// UDA controlling extra attributes for a field.
struct FieldParam {
    string value;
}

/** Create SQL for creating tables if not exists
 *
 * Params:
 * Types = types of structs which will be a tables
 *         name of struct -> name of table
 *         name of field -> name of column
 *
 * To change the name of the table:
 * ---
 * @TableName("my_name")
 * struct Foo {}
 * ---
 */
auto buildSchema(Types...)() {
    import std.array : appender;
    import std.algorithm : joiner;

    auto ret = appender!string;
    foreach (T; Types) {
        static if (is(T == struct)) {
            ret.put("CREATE TABLE IF NOT EXISTS ");
            ret.put(tableName!T);
            ret.put(" (\n");
            ret.put(fieldToCol!("", T)().joiner(",\n"));
            ret.put(");\n");
        } else
            static assert(0, "not supported non-struct type");
    }
    return ret.data;
}

unittest {
    static struct Foo {
        ulong id;
        float value;
        ulong ts;
    }

    static struct Bar {
        ulong id;
        string text;
        ulong ts;
    }

    assert(buildSchema!(Foo, Bar) == `CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
'value' REAL,
'ts' INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS Bar (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
'text' TEXT,
'ts' INTEGER NOT NULL);
`);
}

@("shall create a schema with a table name derived from the UDA")
unittest {
    @TableName("my_table")
    static struct Foo {
        ulong id;
    }

    assert(buildSchema!(Foo) == `CREATE TABLE IF NOT EXISTS my_table (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL);
`);
}

@("shall create a schema with an integer column that may be NULL")
unittest {
    static struct Foo {
        ulong id;
        @FieldParam("")
        ulong int_;
    }

    assert(buildSchema!(Foo) == `CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
'int_' INTEGER);
`);
}

import std.format : format, formattedWrite;
import std.traits;
import std.meta : Filter;

package:

enum IDNAME = "id";
enum SEPARATOR = ".";

string tableName(T)() {
    enum nameAttrs = getUDAs!(T, TableName);
    static assert(nameAttrs.length == 0 || nameAttrs.length == 1,
            "Found multiple TableName UDAs on " ~ T.stringof);
    enum hasName = nameAttrs.length;
    static if (hasName) {
        return nameAttrs[0].value;
    } else
        return T.stringof;
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

private:

string[] fieldToCol(string name, T)(string prefix = "") {
    enum isFieldUDA(alias T) = is(typeof(T) == FieldParam);

    static if (!is(T == struct))
        static assert("Building a schema from type is not supported: " ~ T.stringof);

    T t;
    string[] ret;
    foreach (i, f; t.tupleof) {
        enum fname = __traits(identifier, t.tupleof[i]);
        alias F = typeof(f);
        auto np = prefix ~ (name.length ? name ~ SEPARATOR : "");

        enum udas = Filter!(isFieldUDA, getUDAs!(t.tupleof[i], FieldParam));

        static if (is(F == struct))
            ret ~= fieldToCol!(fname, F)(np);
        else
            ret ~= fieldToColInternal!(fname, F, udas)(np);
    }
    return ret;
}

private string[] fieldToColInternal(string name, T, FieldUDAs...)(string prefix) {
    enum bool isFieldParam(alias T) = is(typeof(T) == FieldParam);

    static if (name == IDNAME)
        return ["'" ~ IDNAME ~ "' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL"];
    else {
        string type, param;

        enum paramAttrs = Filter!(isFieldParam, FieldUDAs);
        static assert(paramAttrs.length == 0 || paramAttrs.length == 1,
                "Found multiple FieldParam UDAs on " ~ T.stringof);
        enum hasParam = paramAttrs.length;
        static if (hasParam)
            param = paramAttrs[0].value;

        enum NOTNULL = " NOT NULL";
        static if (isFloatingPoint!T)
            type = "REAL";
        else static if (isNumeric!T || is(T == bool)) {
            type = "INTEGER";
            static if (!hasParam)
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
