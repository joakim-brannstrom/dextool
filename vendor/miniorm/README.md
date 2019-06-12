# Mini ORM for SQLite3

This is a simple ORM layer for d2sqlite3.

The architecture separate the database from the SQL tree construction. This is
to make it possible to use as an ORM layer for other type of databases in the
future.

## Example

Very simple ORM with single backend (SQLite3).

```d
    auto db = Miniorm("test.db");
    db.run(schema);

    db.run(delete_!Foo.where("ts <", Clock.currTime));

    db.run(insert!Foo, Foo(0, "hello", Clock.currTime), Foo(20, "world", Clock.currTime));
    db.run(insert!Foo, Foo(0, "hello", Clock.currTime), Foo(0, "world", Clock.currTime));

    import std.random : uniform;

    db.run(insert!Bar, Bar(0, uniform(0, 10), Baz("one", 3.14)));

    db.run(insertOrReplace!Foo, Foo(1, "hello", Clock.currTime), Foo(3, "world", Clock.currTime));
```

See [example/source/app.d](example/source/app.d)

# Credit

Oleg Butko (deviator) for writing and publishing MicroORM which MiniORM is
based on. Without MicroORM this library would not have seen the light of day.
