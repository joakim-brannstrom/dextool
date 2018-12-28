/++
Managing query results.

Authors:
    Nicolas Sicard (biozic) and other contributors at $(LINK https://github.com/biozic/d2sqlite3)

Copyright:
    Copyright 2011-18 Nicolas Sicard.

License:
    $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+/
module d2sqlite3.results;

import d2sqlite3.database;
import d2sqlite3.statement;
import d2sqlite3.sqlite3;
import d2sqlite3.internal.util;

import std.conv : to;
import std.exception : enforce;
import std.string : format;
import std.typecons : Nullable;

/// Set _UnlockNotify version if compiled with SqliteEnableUnlockNotify or SqliteFakeUnlockNotify
version (SqliteEnableUnlockNotify)
    version = _UnlockNotify;
else version (SqliteFakeUnlockNotify)
    version = _UnlockNotify;

/++
An input range interface to access the rows resulting from an SQL query.

The elements of the range are `Row` structs. A `Row` is just a view of the current
row when iterating the results of a `ResultRange`. It becomes invalid as soon as
`ResultRange.popFront()` is called (it contains undefined data afterwards). Use
`cached` to store the content of rows past the execution of the statement.

Instances of this struct are typically returned by `Database.execute()` or
`Statement.execute()`.
+/
struct ResultRange {
private:
    Statement statement;
    int state = SQLITE_DONE;
    int colCount = 0;
    Row current;

package(d2sqlite3):
    this(Statement statement) {
        if (!statement.empty) {
            version (_UnlockNotify)
                state = sqlite3_blocking_step(statement);
            else
                state = sqlite3_step(statement.handle);
        } else
            state = SQLITE_DONE;

        enforce(state == SQLITE_ROW || state == SQLITE_DONE,
                new SqliteException(errmsg(statement.handle), state));

        this.statement = statement;
        colCount = sqlite3_column_count(statement.handle);
        current = Row(statement, colCount);
    }

    version (_UnlockNotify) {
        auto sqlite3_blocking_step(Statement statement) {
            int rc;
            while (SQLITE_LOCKED == (rc = sqlite3_step(statement.handle))) {
                rc = statement.waitForUnlockNotify();
                if (rc != SQLITE_OK)
                    break;
                sqlite3_reset(statement.handle);
            }
            return rc;
        }
    }

public:
    /++
    Range interface.
    +/
    bool empty() @property {
        return state == SQLITE_DONE;
    }

    /// ditto
    ref Row front() return @property {
        assert(!empty, "no rows available");
        return current;
    }

    /// ditto
    void popFront() {
        assert(!empty, "no rows available");
        version (_UnlockNotify)
            state = sqlite3_blocking_step(statement);
        else
            state = sqlite3_step(statement.handle);
        current = Row(statement, colCount);
        enforce(state == SQLITE_DONE || state == SQLITE_ROW,
                new SqliteException(errmsg(statement.handle), state));
    }

    /++
    Gets only the first value of the first row returned by the execution of the statement.
    +/
    auto oneValue(T)() {
        return front.peek!T(0);
    }
    ///
    unittest {
        auto db = Database(":memory:");
        db.execute("CREATE TABLE test (val INTEGER)");
        auto count = db.execute("SELECT count(*) FROM test").oneValue!long;
        assert(count == 0);
    }
}
///
unittest {
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (i INTEGER);
            INSERT INTO test VALUES (1);
            INSERT INTO test VALUES (2);");

    auto results = db.execute("SELECT * FROM test");
    assert(!results.empty);
    assert(results.front.peek!long(0) == 1);
    results.popFront();
    assert(!results.empty);
    assert(results.front.peek!long(0) == 2);
    results.popFront();
    assert(results.empty);
}

/++
A row returned when stepping over an SQLite prepared statement.

The data of each column can be retrieved:
$(UL
    $(LI using Row as a random-access range of ColumnData.)
    $(LI using the more direct peek functions.)
)

Warning:
    The data of the row is invalid when the next row is accessed (after a call to
    `ResultRange.popFront()`).
+/
struct Row {
    import std.traits : isBoolean, isIntegral, isSomeChar, isFloatingPoint, isSomeString, isArray;
    import std.traits : isInstanceOf, TemplateArgsOf;

private:
    Statement statement;
    int frontIndex = 0;
    int backIndex = -1;

    this(Statement statement, int colCount) nothrow {
        this.statement = statement;
        backIndex = colCount - 1;
    }

public:
    /// Range interface.
    bool empty() const @property nothrow {
        return length == 0;
    }

    /// ditto
    ColumnData front() @property {
        assertInitialized();
        return opIndex(0);
    }

    /// ditto
    void popFront() nothrow {
        assertInitialized();
        frontIndex++;
    }

    /// ditto
    Row save() @property {
        return this;
    }

    /// ditto
    ColumnData back() @property {
        assertInitialized();
        return opIndex(backIndex - frontIndex);
    }

    /// ditto
    void popBack() nothrow {
        assertInitialized();
        backIndex--;
    }

    /// ditto
    size_t length() const @property nothrow {
        return backIndex - frontIndex + 1;
    }

    /// ditto
    ColumnData opIndex(size_t index) {
        assertInitialized();
        auto i = internalIndex(index);
        auto type = sqlite3_column_type(statement.handle, i);
        final switch (type) {
        case SqliteType.INTEGER:
            return ColumnData(peek!long(index));

        case SqliteType.FLOAT:
            return ColumnData(peek!double(index));

        case SqliteType.TEXT:
            return ColumnData(peek!string(index));

        case SqliteType.BLOB:
            return ColumnData(peek!(Blob, PeekMode.copy)(index));

        case SqliteType.NULL:
            return ColumnData(null);
        }
    }

    /// Ditto
    ColumnData opIndex(string columnName) {
        return opIndex(indexForName(columnName));
    }

    /++
    Returns the data of a column directly.

    Contrary to `opIndex`, the `peek` functions return the data directly, automatically cast to T,
    without the overhead of using a wrapping type (`ColumnData`).

    When using `peek` to retrieve an array or a string, you can use either:
        $(UL
            $(LI `peek!(..., PeekMode.copy)(index)`,
              in which case the function returns a copy of the data that will outlive the step
              to the next row,
            or)
            $(LI `peek!(..., PeekMode.slice)(index)`,
              in which case a slice of SQLite's internal buffer is returned (see Warnings).)
        )

    Params:
        T = The type of the returned data. T must be a boolean, a built-in numeric type, a
        string, an array or a `Nullable`.
        $(TABLE
            $(TR
                $(TH Condition on T)
                $(TH Requested database type)
            )
            $(TR
                $(TD `isIntegral!T || isBoolean!T`)
                $(TD INTEGER)
            )
            $(TR
                $(TD `isFloatingPoint!T`)
                $(TD FLOAT)
            )
            $(TR
                $(TD `isSomeString!T`)
                $(TD TEXT)
            )
            $(TR
                $(TD `isArray!T`)
                $(TD BLOB)
            )
            $(TR
                $(TD `is(T == Nullable!U, U...)`)
                $(TD NULL or U)
            )
        )

        index = The index of the column in the prepared statement or
        the name of the column, as specified in the prepared statement
        with an AS clause. The index of the first column is 0.

    Returns:
        A value of type T. The returned value results from SQLite's own conversion rules:
        see $(LINK http://www.sqlite.org/c3ref/column_blob.html) and
        $(LINK http://www.sqlite.org/lang_expr.html#castexpr). It's then converted
        to T using `std.conv.to!T`.

    Warnings:
        When using `PeekMode.slice`, the data of the slice will be $(B invalidated)
        when the next row is accessed. A copy of the data has to be made somehow for it to
        outlive the next step on the same statement.

        When using referring to the column by name, the names of all the columns are
        tested each time this function is called: use
        numeric indexing for better performance.
    +/
    T peek(T)(size_t index) if (isBoolean!T || isIntegral!T || isSomeChar!T) {
        assertInitialized();
        return sqlite3_column_int64(statement.handle, internalIndex(index)).to!T;
    }

    /// ditto
    T peek(T)(size_t index) if (isFloatingPoint!T) {
        assertInitialized();
        return sqlite3_column_double(statement.handle, internalIndex(index)).to!T;
    }

    /// ditto
    T peek(T, PeekMode mode = PeekMode.copy)(size_t index) if (isSomeString!T) {
        import core.stdc.string : strlen, memcpy;

        assertInitialized();
        auto i = internalIndex(index);
        auto str = cast(const(char)*) sqlite3_column_text(statement.handle, i);

        if (str is null)
            return null;

        auto length = strlen(str);
        static if (mode == PeekMode.copy) {
            char[] text;
            text.length = length;
            memcpy(text.ptr, str, length);
            return text.to!T;
        } else static if (mode == PeekMode.slice)
            return cast(T) str[0 .. length];
        else
            static assert(false);
    }

    /// ditto
    T peek(T, PeekMode mode = PeekMode.copy)(size_t index)
            if (isArray!T && !isSomeString!T) {
        assertInitialized();
        auto i = internalIndex(index);
        auto ptr = sqlite3_column_blob(statement.handle, i);
        auto length = sqlite3_column_bytes(statement.handle, i);
        static if (mode == PeekMode.copy) {
            import core.stdc.string : memcpy;

            ubyte[] blob;
            blob.length = length;
            memcpy(blob.ptr, ptr, length);
            return cast(T) blob;
        } else static if (mode == PeekMode.slice)
            return cast(T) ptr[0 .. length];
        else
            static assert(false);
    }

    /// ditto
    T peek(T)(size_t index)
            if (isInstanceOf!(Nullable, T) && !isArray!(TemplateArgsOf!T[0])
                && !isSomeString!(TemplateArgsOf!T[0])) {
        assertInitialized();
        alias U = TemplateArgsOf!T[0];
        if (sqlite3_column_type(statement.handle, internalIndex(index)) == SqliteType.NULL)
            return T.init;
        return T(peek!U(index));
    }

    /// ditto
    T peek(T, PeekMode mode = PeekMode.copy)(size_t index)
            if (isInstanceOf!(Nullable, T) && (isArray!(TemplateArgsOf!T[0])
                || isSomeString!(TemplateArgsOf!T[0]))) {
        assertInitialized();
        alias U = TemplateArgsOf!T[0];
        if (sqlite3_column_type(statement.handle, internalIndex(index)) == SqliteType.NULL)
            return T.init;
        return T(peek!(U, mode)(index));
    }

    /// ditto
    T peek(T)(string columnName) {
        return peek!T(indexForName(columnName));
    }

    /++
    Determines the type of the data in a particular column.

    `columnType` returns the type of the actual data in that column, whereas
    `columnDeclaredTypeName` returns the name of the type as declared in the SELECT statement.

    See_Also: $(LINK http://www.sqlite.org/c3ref/column_blob.html) and
    $(LINK http://www.sqlite.org/c3ref/column_decltype.html).
    +/
    SqliteType columnType(size_t index) {
        assertInitialized();
        return cast(SqliteType) sqlite3_column_type(statement.handle, internalIndex(index));
    }
    /// Ditto
    SqliteType columnType(string columnName) {
        return columnType(indexForName(columnName));
    }
    /// Ditto
    string columnDeclaredTypeName(size_t index) {
        assertInitialized();
        return sqlite3_column_decltype(statement.handle, internalIndex(index)).to!string;
    }
    /// Ditto
    string columnDeclaredTypeName(string columnName) {
        return columnDeclaredTypeName(indexForName(columnName));
    }
    ///
    unittest {
        auto db = Database(":memory:");
        db.run("CREATE TABLE items (name TEXT, price REAL);
                INSERT INTO items VALUES ('car', 20000);
                INSERT INTO items VALUES ('air', 'free');");

        auto results = db.execute("SELECT name, price FROM items");

        auto row = results.front;
        assert(row.columnType(0) == SqliteType.TEXT);
        assert(row.columnType("price") == SqliteType.FLOAT);
        assert(row.columnDeclaredTypeName(0) == "TEXT");
        assert(row.columnDeclaredTypeName("price") == "REAL");

        results.popFront();
        row = results.front;
        assert(row.columnType(0) == SqliteType.TEXT);
        assert(row.columnType("price") == SqliteType.TEXT);
        assert(row.columnDeclaredTypeName(0) == "TEXT");
        assert(row.columnDeclaredTypeName("price") == "REAL");
    }

    /++
    Determines the name of a particular column.

    See_Also: $(LINK http://www.sqlite.org/c3ref/column_name.html).
    +/
    string columnName(size_t index) {
        assertInitialized();
        return sqlite3_column_name(statement.handle, internalIndex(index)).to!string;
    }
    ///
    unittest {
        auto db = Database(":memory:");
        db.run("CREATE TABLE items (name TEXT, price REAL);
                INSERT INTO items VALUES ('car', 20000);");

        auto row = db.execute("SELECT name, price FROM items").front;
        assert(row.columnName(1) == "price");
    }

    version (SqliteEnableColumnMetadata) {
        /++
        Determines the name of the database, table, or column that is the origin of a
        particular result column in SELECT statement.

        Warning:
        These methods are defined only when this library is compiled with
        `-version=SqliteEnableColumnMetadata`, and SQLite compiled with the
        `SQLITE_ENABLE_COLUMN_METADATA` option defined.

        See_Also: $(LINK http://www.sqlite.org/c3ref/column_database_name.html).
        +/
        string columnDatabaseName(size_t index) {
            assertInitialized();
            return sqlite3_column_database_name(statement.handle, internalIndex(index)).to!string;
        }
        /// Ditto
        string columnDatabaseName(string columnName) {
            return columnDatabaseName(indexForName(columnName));
        }
        /// Ditto
        string columnTableName(size_t index) {
            assertInitialized();
            return sqlite3_column_database_name(statement.handle, internalIndex(index)).to!string;
        }
        /// Ditto
        string columnTableName(string columnName) {
            return columnTableName(indexForName(columnName));
        }
        /// Ditto
        string columnOriginName(size_t index) {
            assertInitialized();
            return sqlite3_column_origin_name(statement.handle, internalIndex(index)).to!string;
        }
        /// Ditto
        string columnOriginName(string columnName) {
            return columnOriginName(indexForName(columnName));
        }
    }

    /++
    Returns a struct with field members populated from the row's data.

    Neither the names of the fields nor the names of the columns are checked. The fields
    are filled with the columns' data in order. Thus, the order of the struct members must be the
    same as the order of the columns in the prepared statement.

    SQLite's conversion rules will be used. For instance, if a string field has the same rank
    as an INTEGER column, the field's data will be the string representation of the integer.
    +/
    T as(T)() if (is(T == struct)) {
        import std.traits : FieldTypeTuple, FieldNameTuple;

        alias FieldTypes = FieldTypeTuple!T;
        T obj;
        foreach (i, fieldName; FieldNameTuple!T)
            __traits(getMember, obj, fieldName) = peek!(FieldTypes[i])(i);
        return obj;
    }
    ///
    unittest {
        struct Item {
            int _id;
            string name;
        }

        auto db = Database(":memory:");
        db.run("CREATE TABLE items (name TEXT);
                INSERT INTO items VALUES ('Light bulb')");

        auto results = db.execute("SELECT rowid AS id, name FROM items");
        auto row = results.front;
        auto thing = row.as!Item();

        assert(thing == Item(1, "Light bulb"));
    }

private:
    int internalIndex(size_t index) {
        assertInitialized();
        auto i = index + frontIndex;
        assert(i >= 0 && i <= backIndex, "invalid column index: %d".format(i));
        assert(i <= int.max, "invalid index value: %d".format(i));
        return cast(int) i;
    }

    int indexForName(string name) {
        assertInitialized();
        assert(name.length, "column with no name");
        foreach (i; frontIndex .. backIndex + 1) {
            assert(i <= int.max, "invalid index value: %d".format(i));
            if (sqlite3_column_name(statement.handle, cast(int) i).to!string == name)
                return i;
        }

        assert(false, "invalid column name: '%s'".format(name));
    }

    void assertInitialized() nothrow {
        assert(!empty, "Accessing elements of an empty row");
        assert(statement.handle !is null, "operation on an empty statement");
    }
}

/// Behavior of the `Row.peek()` method for arrays/strings
enum PeekMode {
    /++
    Return a copy of the data into a new array/string.
    The copy is safe to use after stepping to the next row.
    +/
    copy,

    /++
    Return a slice of the data.
    The slice can point to invalid data after stepping to the next row.
    +/
    slice
}

/++
Some data retrieved from a column.
+/
struct ColumnData {
    import std.traits : isBoolean, isIntegral, isNumeric, isFloatingPoint, isSomeString, isArray;
    import std.variant : Algebraic, VariantException;

    alias SqliteVariant = Algebraic!(long, double, string, Blob, typeof(null));

    private {
        SqliteVariant _value;
        SqliteType _type;
    }

    /++
    Creates a new `ColumnData` from the value.
    +/
    this(T)(inout T value) inout if (isBoolean!T || isIntegral!T) {
        _value = SqliteVariant(value.to!long);
        _type = SqliteType.INTEGER;
    }

    /// ditto
    this(T)(T value) if (isFloatingPoint!T) {
        _value = SqliteVariant(value.to!double);
        _type = SqliteType.FLOAT;
    }

    /// ditto
    this(T)(T value) if (isSomeString!T) {
        if (value is null) {
            _value = SqliteVariant(null);
            _type = SqliteType.NULL;
        } else {
            _value = SqliteVariant(value.to!string);
            _type = SqliteType.TEXT;
        }
    }

    /// ditto
    this(T)(T value) if (isArray!T && !isSomeString!T) {
        if (value is null) {
            _value = SqliteVariant(null);
            _type = SqliteType.NULL;
        } else {
            _value = SqliteVariant(value.to!Blob);
            _type = SqliteType.BLOB;
        }
    }
    /// ditto
    this(T)(T value) if (is(T == typeof(null))) {
        _value = SqliteVariant(null);
        _type = SqliteType.NULL;
    }

    /++
    Returns the Sqlite type of the column.
    +/
    SqliteType type() const nothrow {
        assertInitialized();
        return _type;
    }

    /++
    Returns the data converted to T.

    If the data is NULL, defaultValue is returned.
    +/
    auto as(T)(T defaultValue = T.init)
            if (isBoolean!T || isNumeric!T || isSomeString!T) {
        assertInitialized();

        if (_type == SqliteType.NULL)
            return defaultValue;

        return _value.coerce!T;
    }

    /// ditto
    auto as(T)(T defaultValue = T.init) if (isArray!T && !isSomeString!T) {
        assertInitialized();

        if (_type == SqliteType.NULL)
            return defaultValue;

        Blob data;
        try
            data = _value.get!Blob;
        catch (VariantException e)
            throw new SqliteException("impossible to convert this column to a " ~ T.stringof);

        return cast(T) data;
    }

    /// ditto
    auto as(T : Nullable!U, U...)(T defaultValue = T.init) {
        assertInitialized();

        if (_type == SqliteType.NULL)
            return defaultValue;

        return T(as!U());
    }

    void toString(scope void delegate(const(char)[]) sink) {
        assertInitialized();

        if (_type == SqliteType.NULL)
            sink("null");
        else
            sink(_value.toString);
    }

private:
    void assertInitialized() const nothrow {
        assert(_value.hasValue, "Accessing uninitialized ColumnData");
    }
}

/++
Caches all the results of a query into memory at once.

This allows to keep all the rows returned from a query accessible in any order
and indefinitely.

Returns:
    A `CachedResults` struct that allows to iterate on the rows and their
    columns with an array-like interface.

    The `CachedResults` struct is equivalent to an array of 'rows', which in
    turn can be viewed as either an array of `ColumnData` or as an associative
    array of `ColumnData` indexed by the column names.
+/
CachedResults cached(ResultRange results) {
    return CachedResults(results);
}
///
unittest {
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (msg TEXT, num FLOAT);
            INSERT INTO test (msg, num) VALUES ('ABC', 123);
            INSERT INTO test (msg, num) VALUES ('DEF', 456);");

    auto results = db.execute("SELECT * FROM test").cached;
    assert(results.length == 2);
    assert(results[0][0].as!string == "ABC");
    assert(results[0][1].as!int == 123);
    assert(results[1]["msg"].as!string == "DEF");
    assert(results[1]["num"].as!int == 456);
}

/++
Stores all the results of a query.

The `CachedResults` struct is equivalent to an array of 'rows', which in
turn can be viewed as either an array of `ColumnData` or as an associative
array of `ColumnData` indexed by the column names.

Unlike `ResultRange`, `CachedResults` is a random-access range of rows, and its
data always remain available.

See_Also:
    `cached` for an example.
+/
struct CachedResults {
    import std.array : appender;

    // A row of retrieved data
    struct CachedRow {
        ColumnData[] columns;
        alias columns this;

        size_t[string] columnIndexes;

        private this(Row row, size_t[string] columnIndexes) {
            this.columnIndexes = columnIndexes;

            auto colapp = appender!(ColumnData[]);
            foreach (i; 0 .. row.length)
                colapp.put(row[i]);
            columns = colapp.data;
        }

        // Returns the data at the given index in the row.
        ColumnData opIndex(size_t index) {
            return columns[index];
        }

        // Returns the data at the given column.
        ColumnData opIndex(string name) {
            auto index = name in columnIndexes;
            assert(index, "unknown column name: %s".format(name));
            return columns[*index];
        }
    }

    // All the rows returned by the query.
    CachedRow[] rows;
    alias rows this;

    private size_t[string] columnIndexes;

    this(ResultRange results) {
        if (!results.empty) {
            auto first = results.front;
            foreach (i; 0 .. first.length) {
                assert(i <= int.max, "invalid column index value: %d".format(i));
                auto name = sqlite3_column_name(results.statement.handle, cast(int) i).to!string;
                columnIndexes[name] = i;
            }
        }

        auto rowapp = appender!(CachedRow[]);
        while (!results.empty) {
            rowapp.put(CachedRow(results.front, columnIndexes));
            results.popFront();
        }
        rows = rowapp.data;
    }
}
