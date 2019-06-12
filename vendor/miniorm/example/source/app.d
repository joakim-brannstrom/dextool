import std.algorithm;
import std.datetime;
import std.stdio;

import miniorm;

struct Foo {
    ulong id;
    string text;
    SysTime ts;
}

struct Baz {
    string one;
    double two;
}

struct Bar {
    ulong id;
    float value;
    Baz baz;
}

enum schema = buildSchema!(Foo, Bar);

void main() {
    auto db = Miniorm("test.db");
    db.log = true;
    db.run(schema);

    writeln("Foo count: ", db.run(count!Foo));

    foreach (v; db.run(select!Foo.where("text = ", "hello")))
        writeln(v);

    writeln;

    writeln("Bar count: ", db.run(count!Bar));
    foreach (v; db.run(select!Bar.where("value <", 3)))
        writeln(v);

    db.run(delete_!Foo.where("ts <", Clock.currTime));

    db.run(insert!Foo, Foo(0, "hello", Clock.currTime), Foo(20, "world", Clock.currTime));
    db.run(insert!Foo, Foo(0, "hello", Clock.currTime), Foo(0, "world", Clock.currTime));

    import std.random : uniform;

    db.run(insert!Bar, Bar(0, uniform(0, 10), Baz("one", 3.14)));

    db.run(insertOrReplace!Foo, Foo(1, "hello", Clock.currTime), Foo(3, "world", Clock.currTime));
}
