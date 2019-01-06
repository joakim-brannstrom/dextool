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
 * prefix = prefix to use for the tables that are created.
 *
 * To change the name of the table:
 * ---
 * @TableName("my_name")
 * struct Foo {}
 * ---
 */
auto buildSchema(Types...)(string prefix = null) {
    import std.algorithm : joiner, map;
    import std.array : appender, array;
    import std.range : only;

    auto ret = appender!string;
    foreach (T; Types) {
        static if (is(T == struct)) {
            ret.put("CREATE TABLE IF NOT EXISTS ");
            ret.put(prefix);
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

    buildSchema!(Foo, Bar).shouldEqual(`CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY,
'value' REAL NOT NULL,
'ts' INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS Bar (
'id' INTEGER PRIMARY KEY,
'text' TEXT NOT NULL,
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
'id' INTEGER PRIMARY KEY);
`);
}

@("shall create a schema with an integer column that may be NULL")
unittest {
    static struct Foo {
        ulong id;
        @ColumnParam("")
        ulong int_;
    }

    buildSchema!(Foo).shouldEqual(`CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY,
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
'id' INTEGER PRIMARY KEY,
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
'id' INTEGER PRIMARY KEY,
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
'id' INTEGER PRIMARY KEY,
'version' INTEGER NOT NULL);
`, buildSchema!(Foo));
}

@("shall create a schema with a table name derived from the UDA with specified prefix")
unittest {
    @TableName("my_table")
    static struct Foo {
        ulong id;
    }

    buildSchema!Foo("new_").shouldEqual(`CREATE TABLE IF NOT EXISTS new_my_table (
'id' INTEGER PRIMARY KEY);
`);
}

@("shall create a schema with a column of type DATETIME")
unittest {
    import std.datetime : SysTime;

    static struct Foo {
        ulong id;
        SysTime timestamp;
    }

    buildSchema!Foo.shouldEqual(`CREATE TABLE IF NOT EXISTS Foo (
'id' INTEGER PRIMARY KEY,
'timestamp' DATETIME NOT NULL);
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
    /// The type is user defined
    string columnType;
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
        return quoteColumnName ~ " " ~ columnType ~ columnParam;
    }
}

FieldColumn[] fieldToCol(string name, T)(string prefix = "") {
    return fieldToColRecurse!(name, T, 0)(prefix);
}

private:

FieldColumn[] fieldToColRecurse(string name, T, ulong depth)(string prefix) {
    import std.datetime : SysTime;
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

        static if (is(F == SysTime))
            ret ~= fieldToColInternal!(fname, F, depth, udas)(np);
        else static if (is(F == struct))
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
    import std.datetime : SysTime;
    import std.traits : OriginalType;

    enum bool isFieldParam(alias T) = is(typeof(T) == ColumnParam);
    enum bool isFieldName(alias T) = is(typeof(T) == ColumnName);

    static if (name == IDNAME && depth == 0)
        return [FieldColumn(prefix ~ name, prefix ~ IDNAME, "INTEGER", " PRIMARY KEY", true)];
    else {
        string type, param;

        enum paramAttrs = Filter!(isFieldParam, FieldUDAs);
        static assert(paramAttrs.length == 0 || paramAttrs.length == 1,
                "Found multiple ColumnParam UDAs on " ~ T.stringof);
        enum hasParam = paramAttrs.length;
        static if (hasParam) {
            static if (paramAttrs[0].value.length == 0)
                param = "";
            else
                param = " " ~ paramAttrs[0].value;
        } else
            param = " NOT NULL";

        static if (is(T == enum))
            alias originalT = OriginalType!T;
        else
            alias originalT = T;

        static if (isFloatingPoint!originalT)
            type = "REAL";
        else static if (isNumeric!originalT || is(originalT == bool)) {
            type = "INTEGER";
        } else static if (isSomeString!originalT)
            type = "TEXT";
        else static if (isArray!originalT)
            type = "BLOB";
        else static if (is(originalT == SysTime)) {
            type = "DATETIME";
        } else
            static assert(0, "unsupported type: " ~ T.stringof);

        string columnName = name;

        enum nameAttr = Filter!(isFieldName, FieldUDAs);
        static assert(nameAttr.length == 0 || nameAttr.length == 1,
                "Found multiple ColumnName UDAs on " ~ T.stringof);
        static if (nameAttr.length)
            columnName = nameAttr[0].value;

        return [FieldColumn(prefix ~ name, prefix ~ columnName, type, param)];
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

    enum shouldWorkAtCompileTime = fieldToCol!("", Bar);

    fieldToCol!("", Bar)().map!"a.toColumn".shouldEqual(["'id' INTEGER PRIMARY KEY",
            "'abc' REAL NOT NULL", "'foo.xx' REAL NOT NULL", "'foo.yy' TEXT NOT NULL",
            "'foo.baz.a' TEXT NOT NULL", "'foo.baz.b' TEXT NOT NULL",
            "'foo.zz' INTEGER NOT NULL", "'baz' TEXT NOT NULL", "'data' BLOB NOT NULL"]);
}
