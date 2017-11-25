/+
This module is part of d2sqlite3.

Authors:
    Nicolas Sicard (biozic) and other contributors at $(LINK https://github.com/biozic/d2sqlite3)

Copyright:
    Copyright 2011-17 Nicolas Sicard.

License:
    $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+/
module d2sqlite3.internal.util;

import std.traits : isBoolean, isIntegral, isFloatingPoint, isSomeString,
    isArray, isStaticArray, isDynamicArray;
import std.typecons : Nullable;
import d2sqlite3.sqlite3;
import d2sqlite3.internal.memory;

package(d2sqlite3):

string errmsg(sqlite3* db)
{
    import std.conv : to;
    return sqlite3_errmsg(db).to!string;
}

string errmsg(sqlite3_stmt* stmt)
{
    return errmsg(sqlite3_db_handle(stmt));
}

auto byStatement(string sql)
{
    static struct ByStatement
    {
        string sql;
        size_t end;

        this(string sql)
        {
            this.sql = sql;
            end = findEnd();
        }

        bool empty()
        {
            return !sql.length;
        }

        string front()
        {
            return sql[0 .. end];
        }

        void popFront()
        {
            sql = sql[end .. $];
            end = findEnd();
        }

    private:
        size_t findEnd()
        {
            import std.algorithm : countUntil;
            import std.string : toStringz;

            size_t pos;
            bool complete;
            do
            {
                auto tail = sql[pos .. $];
                immutable offset = tail.countUntil(';') + 1;
                pos += offset;
                if (offset == 0)
                    pos = sql.length;
                auto part = sql[0 .. pos];
                complete = cast(bool) sqlite3_complete(part.toStringz);
            }
            while (!complete && pos < sql.length);
            return pos;
        }
    }

    return ByStatement(sql);
}
unittest
{
    import std.algorithm : equal, map;
    import std.string : strip;

    auto sql = "CREATE TABLE test (dummy);
        CREATE TRIGGER trig INSERT ON test BEGIN SELECT 1; SELECT 'a;b'; END;
        SELECT 'c;d';;
        CREATE";
    assert(equal(sql.byStatement.map!(s => s.strip), [
        "CREATE TABLE test (dummy);",
        "CREATE TRIGGER trig INSERT ON test BEGIN SELECT 1; SELECT 'a;b'; END;",
        "SELECT 'c;d';",
        ";",
        "CREATE"
    ]));
}

// getValue and setResult function templates
// used by createFunction and createAggregate

auto getValue(T)(sqlite3_value* argv)
    if (isBoolean!T)
{
    return sqlite3_value_int64(argv) != 0;
}

auto getValue(T)(sqlite3_value* argv)
    if (isIntegral!T)
{
    import std.conv : to;
    return sqlite3_value_int64(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
    if (isFloatingPoint!T)
{
    import std.conv : to;
    if (sqlite3_value_type(argv) == SQLITE_NULL)
        return double.nan;
    return sqlite3_value_double(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
    if (isSomeString!T)
{
    import std.conv : to;
    return (cast(const(char)*) sqlite3_value_text(argv)).to!T;
}

auto getValue(T)(sqlite3_value* argv)
    if (isArray!T && !isSomeString!T)
{
    import std.conv : to;
    import core.stdc.string : memcpy;

    auto n = sqlite3_value_bytes(argv);
    ubyte[] blob;
    blob.length = n;
    memcpy(blob.ptr, sqlite3_value_blob(argv), n);
    return cast(T) blob;
}

auto getValue(T : Nullable!U, U...)(sqlite3_value* argv)
{
    if (sqlite3_value_type(argv) == SQLITE_NULL)
        return T.init;
    return T(getValue!(U[0])(argv));
}

void setResult(T)(sqlite3_context* context, T value)
    if (isIntegral!T || isBoolean!T)
{
    import std.conv : to;
    sqlite3_result_int64(context, value.to!long);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isFloatingPoint!T)
{
    import std.conv : to;
    sqlite3_result_double(context, value.to!double);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isSomeString!T)
{
    import std.conv : to;
    auto val = value.to!string;
    sqlite3_result_text64(context, cast(const(char)*) anchorMem(cast(void*) val.ptr),
        val.length, &releaseMem, SQLITE_UTF8);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isDynamicArray!T && !isSomeString!T)
{
    auto val = cast(void[]) value;
    sqlite3_result_blob64(context, anchorMem(val.ptr), val.length, &releaseMem);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isStaticArray!T)
{
    auto val = cast(void[]) value;
    sqlite3_result_blob64(context, val.ptr, val.sizeof, SQLITE_TRANSIENT);
}

void setResult(T : Nullable!U, U...)(sqlite3_context* context, T value)
{
    if (value.isNull)
        sqlite3_result_null(context);
    else
        setResult(context, value.get);
}

string nothrowFormat(Args...)(string fmt, Args args) nothrow
{
    import std.string : format;
    try
        return fmt.format(args);
    catch (Exception e)
        throw new Error("Error: " ~ e.msg);
}
