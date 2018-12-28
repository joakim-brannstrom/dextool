/++
D2SQLite3 provides a thin and convenient wrapper around the SQLite C API.

Features:
$(UL
    $(LI Use reference-counted structs (`Database`, `Statement`) instead of SQLite objects
    pointers.)
    $(LI Run multistatement SQL code with `Database.run()`.)
    $(LI Use built-in integral types, floating point types, `string`, `immutable(ubyte)[]` and
    `Nullable` types directly: conversions to and from SQLite types is automatic and GC-safe.)
    $(LI Bind multiple values to a prepare statement with `Statement.bindAll()` or
    `Statement.inject()`. It's also possible to bind the fields of a struct automatically with
    `Statement.inject()`.)
    $(LI Handle the results of a query as a range of `Row`s, and the columns of a row
    as a range of `ColumnData` (equivalent of a `Variant` fit for SQLite types).)
    $(LI Access the data in a result row directly, by index or by name,
    with the `Row.peek!T()` methods.)
    $(LI Make a struct out of the data of a row with `Row.as!T()`.)
    $(LI Register D functions as SQLite callbacks, with `Database.setUpdateHook()` $(I et al).)
    $(LI Create new SQLite functions, aggregates or collations out of D functions or delegate,
    with automatic type converions, with `Database.createFunction()` $(I et al).)
    $(LI Store all the rows and columns resulting from a query at once with the `cached` function
    (sometimes useful even if not memory-friendly...).)
    $(LI Use an unlock notification when two or more connections access the same database in
    shared-cache mode, either using SQLite's dedicated API (sqlite_unlock_notify) or using an
    emulated equivalent.)
)

Authors:
    Nicolas Sicard (biozic) and other contributors at $(LINK https://github.com/biozic/d2sqlite3)

Copyright:
    Copyright 2011-18 Nicolas Sicard.

License:
    $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+/
module d2sqlite3;

public import d2sqlite3.library;
public import d2sqlite3.database;
public import d2sqlite3.statement;
public import d2sqlite3.results;
public import d2sqlite3.sqlite3;

///
unittest  // Documentation example
{
    // Note: exception handling is left aside for clarity.
    import d2sqlite3;
    import std.typecons : Nullable;

    // Open a database in memory.
    auto db = Database(":memory:");

    // Create a table
    db.run("DROP TABLE IF EXISTS person;
            CREATE TABLE person (
              id    INTEGER PRIMARY KEY,
              name  TEXT NOT NULL,
              score FLOAT
            )");

    // Prepare an INSERT statement
    Statement statement = db.prepare("INSERT INTO person (name, score)
         VALUES (:name, :score)");

    // Bind values one by one (by parameter name or index)
    statement.bind(":name", "John");
    statement.bind(2, 77.5);
    statement.execute();
    statement.reset(); // Need to reset the statement after execution.

    // Bind muliple values at the same time
    statement.bindAll("John", null);
    statement.execute();
    statement.reset();

    // Bind, execute and reset in one call
    statement.inject("Clara", 88.1);

    // Count the changes
    assert(db.totalChanges == 3);

    // Count the Johns in the table.
    auto count = db.execute("SELECT count(*) FROM person WHERE name == 'John'").oneValue!long;
    assert(count == 2);

    // Read the data from the table lazily
    ResultRange results = db.execute("SELECT * FROM person");
    foreach (Row row; results) {
        // Retrieve "id", which is the column at index 0, and contains an int,
        // e.g. using the peek function (best performance).
        auto id = row.peek!long(0);

        // Retrieve "name", e.g. using opIndex(string), which returns a ColumnData.
        auto name = row["name"].as!string;

        // Retrieve "score", which is at index 2, e.g. using the peek function,
        // using a Nullable type
        auto score = row.peek!(Nullable!double)(2);
        if (!score.isNull) {
            // ...
        }
    }
}
