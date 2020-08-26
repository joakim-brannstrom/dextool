module tests.d;

version (unittest)  : import d2sqlite3;
import std.exception : assertThrown, assertNotThrown;
import std.string : format;
import std.typecons : Nullable;
import std.conv : hexString;

unittest  // Test version of SQLite library
{
    import std.string : startsWith;

    assert(versionString.startsWith("3."));
    assert(versionNumber >= 3_008_007);
}

unittest  // COV
{
    auto ts = threadSafe;
}

unittest  // Configuration logging and db.close()
{
    static extern (C) void loggerCallback(void* arg, int code, const(char)* msg) nothrow {
        ++*(cast(int*) arg);
    }

    int marker = 42;

    shutdown();
    config(SQLITE_CONFIG_MULTITHREAD);
    config(SQLITE_CONFIG_LOG, &loggerCallback, &marker);
    initialize();

    {
        auto db = Database(":memory:");
        try {
            db.run("DROP TABLE wtf");
        } catch (Exception e) {
        }
        db.close();
    }
    assert(marker == 43);

    shutdown();
    config(SQLITE_CONFIG_LOG, null, null);
    initialize();

    {
        auto db = Database(":memory:");
        try {
            db.run("DROP TABLE wtf");
        } catch (Exception e) {
        }
    }
    assert(marker == 43);
}

unittest  // Database.tableColumnMetadata()
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT,
            val FLOAT NOT NULL)");
    assert(db.tableColumnMetadata("test",
            "id") == TableColumnMetadata("INTEGER", "BINARY", false, true, true));
    assert(db.tableColumnMetadata("test", "val") == TableColumnMetadata("FLOAT",
            "BINARY", true, false, false));
}

unittest  // Database.run()
{
    auto db = Database(":memory:");
    int i;
    db.run(`SELECT 1; SELECT 2;`, (ResultRange r) {
        i = r.oneValue!int;
        return false;
    });
    assert(i == 1);
}

unittest  // Database.errorCode()
{
    auto db = Database(":memory:");
    db.run(`SELECT 1;`);
    assert(db.errorCode == SQLITE_OK);
    try
        db.run(`DROP TABLE non_existent`);
    catch (SqliteException e)
        assert(db.errorCode == SQLITE_ERROR);
}

unittest  // Database.config
{
    auto db = Database(":memory:");
    db.run(`
        CREATE TABLE test (val INTEGER);
        CREATE TRIGGER test_trig BEFORE INSERT ON test
        BEGIN
            SELECT RAISE(FAIL, 'Test failed');
        END;
    `);
    int res = 42;
    db.config(SQLITE_DBCONFIG_ENABLE_TRIGGER, 0, &res);
    assert(res == 0);
    db.execute("INSERT INTO test (val) VALUES (1)");
}

unittest  // Database.createFunction(ColumnData[]...)
{
    string myList(ColumnData[] args...) {
        import std.array : appender;
        import std.string : format, join;

        auto app = appender!(string[]);
        foreach (arg; args) {
            if (arg.type == SqliteType.TEXT)
                app.put(`"%s"`.format(arg));
            else
                app.put("%s".format(arg));
        }
        return app.data.join(", ");
    }

    auto db = Database(":memory:");
    db.createFunction("my_list", &myList);
    auto list = db.execute("SELECT my_list(42, 3.14, 'text', x'00FF', NULL)").oneValue!string;
    assert(list == `42, 3.14, "text", [0, 255], null`, list);
}

unittest  // Database.createFunction() exceptions
{
    import std.exception : assertThrown;

    int myFun(int a, int b = 1) {
        return a * b;
    }

    auto db = Database(":memory:");
    db.createFunction("myFun", &myFun);
    assertThrown!SqliteException(db.execute("SELECT myFun()"));
    assertThrown!SqliteException(db.execute("SELECT myFun(1, 2, 3)"));
    assert(db.execute("SELECT myFun(5)").oneValue!int == 5);
    assert(db.execute("SELECT myFun(5, 2)").oneValue!int == 10);

    db.createFunction("myFun", null);
    assertThrown!SqliteException(db.execute("SELECT myFun(5)"));
    assertThrown!SqliteException(db.execute("SELECT myFun(5, 2)"));
}

unittest  // Database.setUpdateHook()
{
    int i;
    auto db = Database(":memory:");
    db.setUpdateHook((int type, string dbName, string tableName, long rowid) {
        assert(type == SQLITE_INSERT);
        assert(dbName == "main");
        assert(tableName == "test");
        assert(rowid == 1);
        i = 42;
    });
    db.run("CREATE TABLE test (val INTEGER);
            INSERT INTO test VALUES (100)");
    assert(i == 42);
    db.setUpdateHook(null);
}

unittest  // Database commit and rollback hooks
{
    int i;
    auto db = Database(":memory:");
    db.setCommitHook({ i = 42; return SQLITE_OK; });
    db.setRollbackHook({ i = 666; });
    db.begin();
    db.execute("CREATE TABLE test (val INTEGER)");
    db.rollback();
    assert(i == 666);
    db.begin();
    db.execute("CREATE TABLE test (val INTEGER)");
    db.commit();
    assert(i == 42);
    db.setCommitHook(null);
    db.setRollbackHook(null);
}

unittest  // Miscellaneous functions
{
    auto db = Database(":memory:");
    assert(db.attachedFilePath("main") is null);
    assert(!db.isReadOnly);
    db.close();
}

unittest  // Execute an SQL statement
{
    auto db = Database(":memory:");
    db.run("");
    db.run("-- This is a comment!");
    db.run(";");
    db.run("ANALYZE; VACUUM;");
}

unittest  // Unexpected multiple statements
{
    auto db = Database(":memory:");
    db.execute("BEGIN; CREATE TABLE test (val INTEGER); ROLLBACK;");
    assertThrown(db.execute("DROP TABLE test"));

    db.execute("CREATE TABLE test (val INTEGER); DROP TABLE test;");
    assertNotThrown(db.execute("DROP TABLE test"));

    db.execute("SELECT 1; CREATE TABLE test (val INTEGER); DROP TABLE test;");
    assertThrown(db.execute("DROP TABLE test"));
}

unittest  // Multiple statements with callback
{
    import std.array : appender;

    auto db = Database(":memory:");
    auto test = appender!string;
    db.run("SELECT 1, 2, 3; SELECT 'A', 'B', 'C';", (ResultRange r) {
        foreach (col; r.front)
            test.put(col.as!string);
        return true;
    });
    assert(test.data == "123ABC");
}

unittest  // Different arguments and result types with createFunction
{
    auto db = Database(":memory:");

    T display(T)(T value) {
        return value;
    }

    db.createFunction("display_integer", &display!int);
    db.createFunction("display_float", &display!double);
    db.createFunction("display_text", &display!string);
    db.createFunction("display_blob", &display!Blob);

    assert(db.execute("SELECT display_integer(42)").oneValue!int == 42);
    assert(db.execute("SELECT display_float(3.14)").oneValue!double == 3.14);
    assert(db.execute("SELECT display_text('ABC')").oneValue!string == "ABC");
    assert(db.execute("SELECT display_blob(x'ABCD')").oneValue!Blob == cast(Blob) hexString!"ABCD");

    assert(db.execute("SELECT display_integer(NULL)").oneValue!int == 0);
    assert(db.execute("SELECT display_float(NULL)").oneValue!double == 0.0);
    assert(db.execute("SELECT display_text(NULL)").oneValue!string is null);
    assert(db.execute("SELECT display_blob(NULL)").oneValue!(Blob) is null);
}

unittest  // Different Nullable argument types with createFunction
{
    auto db = Database(":memory:");

    auto display(T : Nullable!U, U...)(T value) {
        if (value.isNull)
            return T.init;
        return value;
    }

    db.createFunction("display_integer", &display!(Nullable!int));
    db.createFunction("display_float", &display!(Nullable!double));
    db.createFunction("display_text", &display!(Nullable!string));
    db.createFunction("display_blob", &display!(Nullable!Blob));

    assert(db.execute("SELECT display_integer(42)").oneValue!(Nullable!int) == 42);
    assert(db.execute("SELECT display_float(3.14)").oneValue!(Nullable!double) == 3.14);
    assert(db.execute("SELECT display_text('ABC')").oneValue!(Nullable!string) == "ABC");
    assert(db.execute("SELECT display_blob(x'ABCD')")
            .oneValue!(Nullable!Blob) == cast(Blob) hexString!"ABCD");

    assert(db.execute("SELECT display_integer(NULL)").oneValue!(Nullable!int).isNull);
    assert(db.execute("SELECT display_float(NULL)").oneValue!(Nullable!double).isNull);
    assert(db.execute("SELECT display_text(NULL)").oneValue!(Nullable!string).isNull);
    assert(db.execute("SELECT display_blob(NULL)").oneValue!(Nullable!Blob).isNull);
}

unittest  // Callable struct with createFunction
{
    import std.functional : toDelegate;

    struct Fun {
        int factor;

        this(int factor) {
            this.factor = factor;
        }

        int opCall(int value) {
            return value * factor;
        }
    }

    auto f = Fun(2);
    auto db = Database(":memory:");
    db.createFunction("my_fun", toDelegate(f));
    assert(db.execute("SELECT my_fun(4)").oneValue!int == 8);
}

unittest  // Callbacks
{
    bool wasTraced = false;
    bool wasProfiled = false;
    bool hasProgressed = false;

    auto db = Database(":memory:");
    db.setTraceCallback((string s) { wasTraced = true; });
    db.execute("SELECT * FROM sqlite_master;");
    assert(wasTraced);
    db.setProfileCallback((string s, ulong t) { wasProfiled = true; });
    db.execute("SELECT * FROM sqlite_master;");
    assert(wasProfiled);

    db.setProgressHandler(1, { hasProgressed = true; return 0; });
    db.execute("SELECT * FROM sqlite_master;");
    assert(hasProgressed);
}

unittest  // Statement.oneValue()
{
    Statement statement;
    {
        auto db = Database(":memory:");
        statement = db.prepare(" SELECT 42 ");
    }
    assert(statement.execute.oneValue!int == 42);
}

unittest  // Statement.finalize()
{
    auto db = Database(":memory:");
    auto statement = db.prepare(" SELECT 42 ");
    statement.finalize();
}

unittest  // Simple parameters binding
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    statement.bind(1, 36);
    statement.clearBindings();
    statement.bind(1, 42);
    statement.execute();
    statement.reset();
    statement.bind(1, 42);
    statement.execute();

    assert(db.lastInsertRowid == 2);
    assert(db.changes == 1);
    assert(db.totalChanges == 2);

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
        assert(row.peek!int(0) == 42);
}

unittest  // Multiple parameters binding
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (:i, @f, $t)");

    assert(statement.parameterCount == 3);
    assert(statement.parameterName(2) == "@f");
    assert(statement.parameterIndex("$t") == 3);
    assert(statement.parameterIndex(":foo") == 0);

    statement.bind("$t", "TEXT");
    statement.bind(":i", 42);
    statement.bind("@f", 3.14);
    statement.execute();
    statement.reset();
    statement.bind(1, 42);
    statement.bind(2, 3.14);
    statement.bind(3, "TEXT");
    statement.execute();

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results) {
        assert(row.length == 3);
        assert(row.peek!int("i") == 42);
        assert(row.peek!double("f") == 3.14);
        assert(row.peek!string("t") == "TEXT");
    }
}

unittest  // Multiple parameters binding: tuples
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (?, ?, ?)");
    statement.bindAll(42, 3.14, "TEXT");
    statement.execute();

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results) {
        assert(row.length == 3);
        assert(row.peek!int(0) == 42);
        assert(row.peek!double(1) == 3.14);
        assert(row.peek!string(2) == "TEXT");
    }
}

unittest  // Binding/peeking integral values
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val INTEGER)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    statement.inject(cast(byte) 42);
    statement.inject(42U);
    statement.inject(42UL);
    statement.inject('\x2A');

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
        assert(row.peek!long(0) == 42);
}

void foobar() // Binding/peeking floating point values
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val FLOAT)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    statement.inject(42.0F);
    statement.inject(42.0);
    statement.inject(42.0L);
    statement.inject("42");

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
        assert(row.peek!double(0) == 42.0);
}

unittest  // Binding/peeking text values
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val TEXT);
            INSERT INTO test (val) VALUES ('I am a text.')");

    auto results = db.execute("SELECT * FROM test");
    assert(results.front.peek!(string, PeekMode.slice)(0) == "I am a text.");
    assert(results.front.peek!(string, PeekMode.copy)(0) == "I am a text.");

    import std.exception : assertThrown;
    import std.variant : VariantException;

    assertThrown!VariantException(results.front[0].as!Blob);
}

unittest  // Binding/peeking blob values
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val BLOB)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    auto array = cast(Blob)[1, 2, 3];
    statement.inject(array);
    ubyte[3] sarray = [1, 2, 3];
    statement.inject(sarray);

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results) {
        assert(row.peek!(Blob, PeekMode.slice)(0) == [1, 2, 3]);
        assert(row[0].as!Blob == [1, 2, 3]);
    }
}

unittest  // Struct injecting
{
    static struct Test {
        int i;
        double f;
        string t;
    }

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (?, ?, ?)");
    auto test = Test(42, 3.14, "TEXT");
    statement.inject(test);
    statement.inject(Test(42, 3.14, "TEXT"));
    auto itest = cast(immutable) Test(42, 3.14, "TEXT");
    statement.inject(itest);

    auto results = db.execute("SELECT * FROM test");
    assert(!results.empty);
    foreach (row; results) {
        assert(row.length == 3);
        assert(row.peek!int(0) == 42);
        assert(row.peek!double(1) == 3.14);
        assert(row.peek!string(2) == "TEXT");
    }
}

unittest  // Iterable struct injecting
{
    import std.range : iota;

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (a INTEGER, b INTEGER, c INTEGER)");
    auto statement = db.prepare("INSERT INTO test (a, b, c) VALUES (?, ?, ?)");
    statement.inject(iota(0, 3));

    auto results = db.execute("SELECT * FROM test");
    assert(!results.empty);
    foreach (row; results) {
        assert(row.length == 3);
        assert(row.peek!int(0) == 0);
        assert(row.peek!int(1) == 1);
        assert(row.peek!int(2) == 2);
    }
}

unittest  // Injecting nullable
{
    import std.algorithm : map;
    import std.array : array;

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, s TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, s) VALUES (?, ?)");
    statement.inject(Nullable!int(1), "one");
    statement = db.prepare("INSERT INTO test (i) VALUES (?)");
    statement.inject(Nullable!int.init);

    auto results = db.execute("SELECT i FROM test ORDER BY rowid")
        .map!(a => a.peek!(Nullable!int)(0)).array;

    assert(results.length == 2);
    assert(results[0] == 1);
    assert(results[1].isNull);
}

unittest  // Injecting tuple
{
    import std.typecons : tuple;

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (?, ?, ?)");
    statement.inject(tuple(42, 3.14, "TEXT"));

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results) {
        assert(row.length == 3);
        assert(row.peek!int(0) == 42);
        assert(row.peek!double(1) == 3.14);
        assert(row.peek!string(2) == "TEXT");
    }
}

unittest  // Injecting dict
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (a TEXT, b TEXT, c TEXT)");
    auto statement = db.prepare("INSERT INTO test (c, b, a) VALUES (:c, :b, :a)");
    statement.inject([":a": "a", ":b": "b", ":c": "c"]);

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results) {
        assert(row.length == 3);
        assert(row.peek!string(0) == "a");
        assert(row.peek!string(1) == "b");
        assert(row.peek!string(2) == "c");
    }
}

unittest  // Binding Nullable
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (a, b, c, d, e);");

    auto statement = db.prepare("INSERT INTO test (a,b,c,d,e) VALUES (?,?,?,?,?)");
    statement.bind(1, Nullable!int(123));
    statement.bind(2, Nullable!int());
    statement.bind(3, Nullable!(uint, 0)(42));
    statement.bind(4, Nullable!(uint, 0)());
    statement.bind(5, Nullable!bool(false));
    statement.execute();

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results) {
        assert(row.length == 5);
        assert(row.peek!int(0) == 123);
        assert(row.columnType(1) == SqliteType.NULL);
        assert(row.peek!int(2) == 42);
        assert(row.columnType(3) == SqliteType.NULL);
        assert(!row.peek!bool(4));
    }
}

unittest  // Peeking Nullable
{
    auto db = Database(":memory:");
    auto results = db.execute("SELECT 1, NULL, 8.5, NULL");
    foreach (row; results) {
        assert(row.length == 4);
        assert(row.peek!(Nullable!double)(2).get == 8.5);
        assert(row.peek!(Nullable!double)(3).isNull);
        assert(row.peek!(Nullable!(int, 0))(0).get == 1);
        assert(row.peek!(Nullable!(int, 0))(1).isNull);
    }
}

unittest  // GC anchoring test
{
    import core.memory : GC;

    auto db = Database(":memory:");
    auto stmt = db.prepare("SELECT ?");

    auto str = ("I am test string").dup;
    stmt.bind(1, str);
    str = null;

    foreach (_; 0 .. 3) {
        GC.collect();
        GC.minimize();
    }

    ResultRange results = stmt.execute();
    foreach (row; results) {
        assert(row.length == 1);
        assert(row.peek!string(0) == "I am test string");
    }
}

version (unittest) // ResultRange is an input range of Row
{
    import std.range.primitives : isInputRange, ElementType;

    static assert(isInputRange!ResultRange);
    static assert(is(ElementType!ResultRange == Row));
}

unittest  // Statement error
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER NOT NULL)");
    auto stmt = db.prepare("INSERT INTO test (val) VALUES (?)");
    stmt.bind(1, null);
    import std.exception : assertThrown;

    assertThrown!SqliteException(stmt.execute());
}

version (unittest) // Row is a random access range of ColumnData
{
    import std.range.primitives : isRandomAccessRange, ElementType;

    static assert(isRandomAccessRange!Row);
    static assert(is(ElementType!Row == ColumnData));
}

unittest  // Row.init
{
    import core.exception : AssertError;

    Row row;
    assert(row.empty);
    assertThrown!AssertError(row.front);
    assertThrown!AssertError(row.back);
    assertThrown!AssertError(row.popFront);
    assertThrown!AssertError(row.popBack);
    assertThrown!AssertError(row[""]);
    assertThrown!AssertError(row.peek!long(0));
}

unittest  // Peek
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (value);
            INSERT INTO test VALUES (NULL);
            INSERT INTO test VALUES (42);
            INSERT INTO test VALUES (3.14);
            INSERT INTO test VALUES ('ABC');
            INSERT INTO test VALUES (x'DEADBEEF');");

    import std.math : isNaN;

    auto results = db.execute("SELECT * FROM test");
    auto row = results.front;
    assert(row.peek!long(0) == 0);
    assert(row.peek!double(0) == 0);
    assert(row.peek!string(0) is null);
    assert(row.peek!Blob(0) is null);
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 42);
    assert(row.peek!double(0) == 42);
    assert(row.peek!string(0) == "42");
    assert(row.peek!Blob(0) == cast(Blob) "42");
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 3);
    assert(row.peek!double(0) == 3.14);
    assert(row.peek!string(0) == "3.14");
    assert(row.peek!Blob(0) == cast(Blob) "3.14");
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 0);
    assert(row.peek!double(0) == 0.0);
    assert(row.peek!string(0) == "ABC");
    assert(row.peek!Blob(0) == cast(Blob) "ABC");
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 0);
    assert(row.peek!double(0) == 0.0);
    assert(row.peek!string(0) == hexString!"DEADBEEF");
    assert(row.peek!Blob(0) == cast(Blob) hexString!"DEADBEEF");
}

unittest  // Peeking NULL values
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val TEXT);
            INSERT INTO test (val) VALUES (NULL)");

    auto results = db.execute("SELECT * FROM test");
    assert(results.front.peek!bool(0) == false);
    assert(results.front.peek!long(0) == 0);
    assert(results.front.peek!double(0) == 0);
    assert(results.front.peek!string(0) is null);
    assert(results.front.peek!Blob(0) is null);
}

unittest  // Row life-time
{
    auto db = Database(":memory:");
    auto row = db.execute("SELECT 1 AS one").front;
    assert(row[0].as!long == 1);
    assert(row["one"].as!long == 1);
}

unittest  // PeekMode
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (value);
            INSERT INTO test VALUES (x'01020304');
            INSERT INTO test VALUES (x'0A0B0C0D');");

    auto results = db.execute("SELECT * FROM test");
    auto row = results.front;
    auto b1 = row.peek!(Blob, PeekMode.copy)(0);
    auto b2 = row.peek!(Blob, PeekMode.slice)(0);
    results.popFront();
    row = results.front;
    auto b3 = row.peek!(Blob, PeekMode.slice)(0);
    auto b4 = row.peek!(Nullable!Blob, PeekMode.copy)(0);
    assert(b1 == cast(Blob) hexString!"01020304");
    // assert(b2 != cast(Blob) x"01020304"); // PASS if SQLite reuses internal buffer
    // assert(b2 == cast(Blob) x"0A0B0C0D"); // PASS (idem)
    assert(b3 == cast(Blob) hexString!"0A0B0C0D");
    assert(!b4.isNull && b4 == cast(Blob) hexString!"0A0B0C0D");
}

unittest  // Row random-access range interface
{
    import std.array : front, popFront;

    auto db = Database(":memory:");
    db.run("CREATE TABLE test (a INTEGER, b INTEGER, c INTEGER, d INTEGER);
        INSERT INTO test VALUES (1, 2, 3, 4);
        INSERT INTO test VALUES (5, 6, 7, 8);");

    {
        auto results = db.execute("SELECT * FROM test");
        auto values = [1, 2, 3, 4, 5, 6, 7, 8];
        foreach (row; results) {
            while (!row.empty) {
                assert(row.front.as!int == values.front);
                row.popFront();
                values.popFront();
            }
        }
    }

    {
        auto results = db.execute("SELECT * FROM test");
        auto values = [4, 3, 2, 1, 8, 7, 6, 5];
        foreach (row; results) {
            while (!row.empty) {
                assert(row.back.as!int == values.front);
                row.popBack();
                values.popFront();
            }
        }
    }

    {
        auto row = db.execute("SELECT * FROM test").front;
        row.popFront();
        auto copy = row.save();
        row.popFront();
        assert(row.front.as!int == 3);
        assert(copy.front.as!int == 2);
    }
}

unittest  // ColumnData.init
{
    import core.exception : AssertError;

    ColumnData data;
    assertThrown!AssertError(data.type);
    assertThrown!AssertError(data.as!string);
}

unittest  // ColumnData-compatible types
{
    import std.meta : AliasSeq;

    alias AllCases = AliasSeq!(bool, true, int, int.max, float, float.epsilon,
            real, 42.0L, string, "おはよう！", const(ubyte)[], [0x00,
                0xFF], string, "", Nullable!byte, 42);

    void test(Cases...)() {
        auto cd = ColumnData(Cases[1]);
        assert(cd.as!(Cases[0]) == Cases[1]);
        static if (Cases.length > 2)
            test!(Cases[2 .. $])();
    }

    test!AllCases();
}

unittest  // ColumnData.toString
{
    auto db = Database(":memory:");
    auto rc = db.execute("SELECT 42, 3.14, 'foo_bar', x'00FF', NULL").cached;
    assert("%(%s%)".format(rc) == "[42, 3.14, foo_bar, [0, 255], null]");
}

unittest  // CachedResults copies
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (msg TEXT);
            INSERT INTO test (msg) VALUES ('ABC')");

    static getdata(Database db) {
        return db.execute("SELECT * FROM test").cached;
    }

    auto data = getdata(db);
    assert(data.length == 1);
    assert(data[0][0].as!string == "ABC");
}

unittest  // UTF-8
{
    auto db = Database(":memory:");
    bool ran = false;
    db.run("SELECT '\u2019\u2019';", (ResultRange r) {
        assert(r.oneValue!string == "\u2019\u2019");
        ran = true;
        return true;
    });
    assert(ran);
}

unittest  // loadExtension failure test
{
    import std.algorithm : canFind;
    import std.exception : collectExceptionMsg;

    auto db = Database(":memory:");
    auto msg = collectExceptionMsg(db.loadExtension("foobar"));
    //assert(msg.canFind("(not authorized)"));
}
