/++
This module is part of d2sqlite3.

Authors:
    Nicolas Sicard (biozic) and other contributors at $(LINK https://github.com/biozic/d2sqlite3)

Copyright:
    Copyright 2011-17 Nicolas Sicard.

License:
    $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+/
module d2sqlite3.statement;

import d2sqlite3.database;
import d2sqlite3.results;
import d2sqlite3.sqlite3;
import d2sqlite3.internal.memory;
import d2sqlite3.internal.util;

import std.conv : to;
import std.exception : enforce;
import std.string : format, toStringz;
import std.typecons : Nullable;

/// Set _UnlockNotify version if compiled with SqliteEnableUnlockNotify or SqliteFakeUnlockNotify
version (SqliteEnableUnlockNotify) version = _UnlockNotify;
else version (SqliteFakeUnlockNotify) version = _UnlockNotify;

/++
A prepared statement.

This struct is a reference-counted wrapper around a `sqlite3_stmt*` pointer.
Instances of this struct are typically returned by `Database.prepare()`.
+/
struct Statement
{
    import std.meta : allSatisfy;
    import std.traits : isIntegral, isSomeChar, isBoolean, isFloatingPoint,
        isSomeString, isStaticArray, isDynamicArray, isIterable;
    import std.typecons : RefCounted, RefCountedAutoInitialize;

private:

    /// Returns $(D true) if the value can be directly bound to the statement
    enum bool isBindable(T) =
        is(T == typeof(null)) || is(T == void*) || isIntegral!T || isSomeChar!T
        || isBoolean!T || isFloatingPoint!T || isSomeString!T || isStaticArray!T
        || isDynamicArray!T || is(T == Nullable!U, U...);

    struct Payload
    {
        Database db;
        sqlite3_stmt* handle; // null if error or empty statement
        int paramCount;
        debug string sql;

        ~this()
        {
            debug ensureNotInGC!Statement(sql);
            finalize();
        }

        void finalize()
        {
            sqlite3_finalize(handle);
            handle = null;
        }
    }

    RefCounted!(Payload, RefCountedAutoInitialize.no) p;

    void checkResult(int result)
    {
        enforce(result == SQLITE_OK, new SqliteException(errmsg(p.handle), result));
    }

    version (_UnlockNotify)
    {
        auto sqlite3_blocking_prepare_v2(Database db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail)
        {
            int rc;
            while(SQLITE_LOCKED == (rc = sqlite3_prepare_v2(db.handle(), zSql, nByte, ppStmt, pzTail)))
            {
                rc = db.waitForUnlockNotify();
                if(rc != SQLITE_OK) break;
            }
            return rc;
        }
    }

package(d2sqlite3):
    this(Database db, string sql)
    {
        sqlite3_stmt* handle;
        version (_UnlockNotify)
        {
            auto result = sqlite3_blocking_prepare_v2(db, sql.toStringz, sql.length.to!int,
                &handle, null);
        }
        else
        {
            auto result = sqlite3_prepare_v2(db.handle(), sql.toStringz, sql.length.to!int,
                &handle, null);
        }
        enforce(result == SQLITE_OK, new SqliteException(errmsg(db.handle()), result, sql));
        p = Payload(db, handle);
        p.paramCount = sqlite3_bind_parameter_count(p.handle);
        debug p.sql = sql;
    }

    version (_UnlockNotify)
    {
        /// Setup and waits for unlock notify using the provided `IUnlockNotifyHandler`
        auto waitForUnlockNotify()
        {
            return p.db.waitForUnlockNotify();
        }
    }

public:
    /++
    Gets the SQLite internal _handle of the statement.
    +/
    sqlite3_stmt* handle() @property nothrow
    {
        return p.handle;
    }

    /++
    Explicitly finalizes the prepared statement.

    After a call to `finalize()`, the `Statement` object is destroyed and cannot be used.
    +/
    void finalize()
    {
        p.finalize();
        destroy(p);
    }

    /++
    Tells whether the statement is empty (no SQL statement).
    +/
    bool empty() @property nothrow
    {
        return p.handle is null;
    }
    ///
    unittest
    {
        auto db = Database(":memory:");
        auto statement = db.prepare(" ; ");
        assert(statement.empty);
    }

    /++
    Binds values to parameters of this statement, using parameter index.

    Params:
        index = The index of the parameter (starting from 1).

        value = The bound _value. The type of value must be compatible with the SQLite
        types: it must be a boolean or numeric type, a string, an array, null,
        or a Nullable!T where T is any of the previous types.
    +/
    void bind(T)(int index, T value)
        if (is(T == typeof(null)) || is(T == void*))
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        assert(p.handle);
        checkResult(sqlite3_bind_null(p.handle, index));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isIntegral!T || isSomeChar!T || isBoolean!T)
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        assert(p.handle);
        checkResult(sqlite3_bind_int64(p.handle, index, value.to!long));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isFloatingPoint!T)
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        assert(p.handle);
        checkResult(sqlite3_bind_double(p.handle, index, value.to!double));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isSomeString!T)
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        assert(p.handle);
        string str = value.to!string;
        auto ptr = anchorMem(cast(void*) str.ptr);
        checkResult(sqlite3_bind_text64(p.handle, index, cast(const(char)*) ptr, str.length, &releaseMem, SQLITE_UTF8));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isStaticArray!T)
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        assert(p.handle);
        checkResult(sqlite3_bind_blob64(p.handle, index, cast(void*) value.ptr, value.sizeof, SQLITE_TRANSIENT));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isDynamicArray!T && !isSomeString!T)
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        assert(p.handle);
        auto arr = cast(void[]) value;
        checkResult(sqlite3_bind_blob64(p.handle, index, anchorMem(arr.ptr), arr.length, &releaseMem));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (is(T == Nullable!U, U...))
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        if (value.isNull)
        {
            assert(p.handle);
            checkResult(sqlite3_bind_null(p.handle, index));
        }
        else
            bind(index, value.get);
    }

    /++
    Binds values to parameters of this statement, using parameter names.

    Params:
        name = The name of the parameter, including the ':', '@' or '$' that introduced it.

        value = The bound _value. The type of value must be compatible with the SQLite
        types: it must be a boolean or numeric type, a string, an array, null,
        or a Nullable!T where T is any of the previous types.

    Warning:
        While convenient, this overload of `bind` is less performant, because it has to
        retrieve the column index with a call to the SQLite function
        `sqlite3_bind_parameter_index`.
    +/
    void bind(T)(string name, T value)
    in
    {
        assert(name.length);
    }
    body
    {
        assert(p.handle);
        auto index = sqlite3_bind_parameter_index(p.handle, name.toStringz);
        assert(index > 0, "no parameter named '%s'".format(name));
        bind(index, value);
    }

    /++
    Binds all the arguments at once in order.
    +/
    void bindAll(Args...)(Args args)
    in
    {
        assert(Args.length == this.parameterCount, "parameter count mismatch");
    }
    body
    {
        foreach (index, _; Args)
            bind(index + 1, args[index]);
    }

    /++
    Clears the bindings.

    This does not reset the statement. Use `Statement.reset()` for this.
    +/
    void clearBindings()
    {
        assert(p.handle);
        checkResult(sqlite3_clear_bindings(p.handle));
    }

    /++
    Executes the statement and return a (possibly empty) range of results.
    +/
    ResultRange execute()
    {
        return ResultRange(this);
    }

    /++
    Resets a this statement before a new execution.

    Calling this method invalidates any `ResultRange` struct returned by a previous call
    to `Database.execute()` or `Statement.execute()`.

    This does not clear the bindings. Use `Statement.clearBindings()` for this.
    +/
    void reset()
    {
        assert(p.handle);
        checkResult(sqlite3_reset(p.handle));
    }

    /++
    Binds arguments, executes and resets the statement, in one call.

    This convenience function is equivalent to:
    ---
    bindAll(args);
    execute();
    reset();
    ---
    +/
    void inject(Args...)(Args args)
        if (allSatisfy!(isBindable, Args))
    {
        bindAll(args);
        execute();
        reset();
    }

    /++
    Binds the fields of a struct in order, executes and resets the statement, in one call.
    +/
    void inject(T)(auto ref const T obj)
        if (is(T == struct))
    {
        import std.meta : Filter;
        import std.traits : FieldNameTuple;

        enum accesible(string F) = __traits(compiles, __traits(getMember, obj, F));
        enum bindable(string F) = isBindable!(typeof(__traits(getMember, obj, F)));

        alias FieldNames = Filter!(bindable, Filter!(accesible, FieldNameTuple!T));
        assert(FieldNames.length == this.parameterCount, "parameter count mismatch");
        foreach (i, field; FieldNames)
            bind(i + 1, __traits(getMember, obj, field));
        execute();
        reset();
    }

    /++
    Binds iterable values in order, executes and resets the statement, in one call.
    +/
    void inject(T)(auto ref T obj)
        if (!isBindable!T && isIterable!T)
    in
    {
        static if (__traits(compiles, obj.length))
            assert(obj.length == this.parameterCount, "parameter count mismatch");
    }
    body
    {
        static if (__traits(compiles, { foreach (string k, ref v; obj) {} }))
        {
            foreach (string k, ref v; obj) bind(k, v);
        }
        else
        {
            int i = 1;
            foreach (ref v; obj) bind(i++, v);
        }
        execute();
        reset();
    }

    /// Gets the count of bind parameters.
    int parameterCount() nothrow
    {
        assert(p.handle);
        return p.paramCount;
    }

    /++
    Gets the name of the bind parameter at the given index.

    Params:
        index = The index of the parameter (the first parameter has the index 1).

    Returns: The name of the parameter or null is not found or out of range.
    +/
    string parameterName(int index)
    in
    {
        assert(index > 0 && index <= p.paramCount, "parameter index out of range");
    }
    body
    {
        assert(p.handle);
        return sqlite3_bind_parameter_name(p.handle, index).to!string;
    }

    /++
    Gets the index of a bind parameter.

    Returns: The index of the parameter (the first parameter has the index 1)
    or 0 is not found or out of range.
    +/
    int parameterIndex(string name)
    in
    {
        assert(name.length);
    }
    body
    {
        assert(p.handle);
        return sqlite3_bind_parameter_index(p.handle, name.toStringz);
    }
}

/++
Turns $(D_PARAM value) into a _literal that can be used in an SQLite expression.
+/
string literal(T)(T value)
{
    import std.string : replace;
    import std.traits : isBoolean, isNumeric, isSomeString, isArray;

    static if (is(T == typeof(null)))
        return "NULL";
    else static if (isBoolean!T)
        return value ? "1" : "0";
    else static if (isNumeric!T)
        return value.to!string();
    else static if (isSomeString!T)
        return format("'%s'", value.replace("'", "''"));
    else static if (isArray!T)
        return "'X%(%X%)'".format(cast(Blob) value);
    else
        static assert(false, "cannot make a literal of a value of type " ~ T.stringof);
}
///
unittest
{
    assert(null.literal == "NULL");
    assert(false.literal == "0");
    assert(true.literal == "1");
    assert(4.literal == "4");
    assert(4.1.literal == "4.1");
    assert("foo".literal == "'foo'");
    assert("a'b'".literal == "'a''b'''");
    auto a = cast(Blob) x"DEADBEEF";
    assert(a.literal == "'XDEADBEEF'");
}
