module microrm.schema;

import microrm.util;

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
