/**
Copyright: Copyright (c) 2017, Oleg Butko. All rights reserved.
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MIT
Author: Oleg Butko (deviator)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module microrm.schema;

version (unittest) {
    import std.algorithm : map;
    import unit_threaded.assertions;
}

/// UDA controlling the name of the table.
struct TableName {
    string value;
}

/// UDA controlling constraints of a table.
struct TableConstraint {
    string value;
}

/// UDA for foreign keys on a table.
struct TableForeignKey {
    string foreignKey;
    KeyRef r;
    KeyParam p;
}

struct KeyRef {
    string value;
}

struct KeyParam {
    string value;
}

/// UDA controlling extra attributes for a field.
struct ColumnParam {
    string value;
}

/// UDA to control the column name that a field end up as.
struct ColumnName {
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
    import std.algorithm : joiner, map;
    import std.array : appender, array;
    import std.range : only;

    auto ret = appender!string;
    foreach (T; Types) {
        static if (is(T == struct)) {
            ret.put("CREATE TABLE IF NOT EXISTS ");
            ret.put(tableName!T);
            ret.put(" (\n");
            ret.put(only(fieldToCol!("", T)().map!"a.toColumn".array,
                    tableConstraints!T(), tableForeinKeys!T()).joiner.joiner(",\n"));
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
        @ColumnParam("")
        ulong int_;
    }

    assert(buildSchema!(Foo) == `CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
'int_' INTEGER);
`);
}

@("shall create a schema with constraints from UDAs")
unittest {
    @TableConstraint("u UNIQUE p")
    static struct Foo {
        ulong id;
        ulong p;
    }

    assert(buildSchema!(Foo) == `CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
'p' INTEGER NOT NULL,
CONSTRAINT u UNIQUE p);
`, buildSchema!(Foo));
}

@("shall create a schema with a foregin key from UDAs")
unittest {
    @TableForeignKey("p", KeyRef("bar(id)"), KeyParam("ON DELETE CASCADE"))
    static struct Foo {
        ulong id;
        ulong p;
    }

    assert(buildSchema!(Foo) == `CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
'p' INTEGER NOT NULL,
FOREIGN KEY(p) REFERENCES bar(id) ON DELETE CASCADE);
`, buildSchema!(Foo));
}

@("shall create a schema with a name from UDA")
unittest {
    static struct Foo {
        ulong id;
        @ColumnName("version")
        ulong version_;
    }

    assert(buildSchema!(Foo) == `CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
'version' INTEGER NOT NULL);
`, buildSchema!(Foo));
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

string[] tableConstraints(T)() {
    enum constraintAttrs = getUDAs!(T, TableConstraint);
    enum hasConstraints = constraintAttrs.length;

    string[] rval;
    static if (hasConstraints) {
        static foreach (const c; constraintAttrs)
            rval ~= "CONSTRAINT " ~ c.value;
    }
    return rval;
}

string[] tableForeinKeys(T)() {
    enum foreignKeyAttrs = getUDAs!(T, TableForeignKey);
    enum hasForeignKeys = foreignKeyAttrs.length;

    string[] rval;
    static if (hasForeignKeys) {
        static foreach (a; foreignKeyAttrs)
            rval ~= "FOREIGN KEY(" ~ a.foreignKey ~ ") REFERENCES " ~ a.r.value ~ (
                    (a.p.value.length == 0) ? null : " " ~ a.p.value);
    }

    return rval;
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

@("shall derive the field names from the inspected struct")
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

    import std.algorithm;
    import std.utf;

    assert(fieldNames!("", Bar) == ["'id'", "'abc'", "'foo.id'", "'foo.xx'", "'foo.yy'", "'baz'"]);
    fieldToCol!("", Bar).map!"a.quoteIdentifier".shouldEqual(["'id'", "'abc'",
            "'foo.id'", "'foo.xx'", "'foo.yy'", "'baz'"]);
}

struct FieldColumn {
    /// Identifier in the struct.
    string identifier;
    /// Name of the column in the table.
    string columnName;
    /// Parameters for the column when creating the table.
    string columnParam;
    /// If the field is a primary key.
    bool isPrimaryKey;

    string quoteIdentifier() @safe pure nothrow const {
        return "'" ~ identifier ~ "'";
    }

    string quoteColumnName() @safe pure nothrow const {
        return "'" ~ columnName ~ "'";
    }

    string toColumn() @safe pure nothrow const {
        return quoteColumnName ~ " " ~ columnParam;
    }
}

FieldColumn[] fieldToCol(string name, T)(string prefix = "") {
    return fieldToColRecurse!(name, T, 0)(prefix);
}

private:

FieldColumn[] fieldToColRecurse(string name, T, ulong depth)(string prefix) {
    import std.meta : AliasSeq;

    static if (!is(T == struct))
        static assert(
                "Building a schema from a type is only supported for struct's. This type is not supported: "
                ~ T.stringof);

    T t;
    FieldColumn[] ret;
    foreach (i, f; t.tupleof) {
        enum fname = __traits(identifier, t.tupleof[i]);
        alias F = typeof(f);
        auto np = prefix ~ (name.length ? name ~ SEPARATOR : "");

        enum udas = AliasSeq!(getUDAs!(t.tupleof[i], ColumnParam),
                    getUDAs!(t.tupleof[i], ColumnName));

        static if (is(F == struct))
            ret ~= fieldToColRecurse!(fname, F, depth + 1)(np);
        else
            ret ~= fieldToColInternal!(fname, F, depth, udas)(np);
    }
    return ret;
}

/**
 * Params:
 *  depth = A primary key can only be at the outer most struct. Any other "id" fields are normal integers.
 */
FieldColumn[] fieldToColInternal(string name, T, ulong depth, FieldUDAs...)(string prefix) {
    enum bool isFieldParam(alias T) = is(typeof(T) == ColumnParam);
    enum bool isFieldName(alias T) = is(typeof(T) == ColumnName);

    static if (name == IDNAME && depth == 0)
        return [FieldColumn(prefix ~ name, prefix ~ IDNAME,
                "INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL", true)];
    else {
        string type, param;

        enum paramAttrs = Filter!(isFieldParam, FieldUDAs);
        static assert(paramAttrs.length == 0 || paramAttrs.length == 1,
                "Found multiple ColumnParam UDAs on " ~ T.stringof);
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

        string columnName = name;

        enum nameAttr = Filter!(isFieldName, FieldUDAs);
        static assert(nameAttr.length == 0 || nameAttr.length == 1,
                "Found multiple ColumnName UDAs on " ~ T.stringof);
        static if (nameAttr.length)
            columnName = nameAttr[0].value;

        return [FieldColumn(prefix ~ name, prefix ~ columnName, type ~ param)];
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

    fieldToCol!("", Bar)().map!"a.toColumn".shouldEqual(
            ["'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL", "'abc' REAL",
            "'foo.xx' REAL", "'foo.yy' TEXT",
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
