import std.stdio;
import std.algorithm;

import microrm;

struct Foo {
    ulong id;
    string text;
    ulong ts;
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

auto cts() @property {
    import std.datetime;

    return Clock.currStdTime;
}

void main() {
    auto db = new MDatabase("test.db");
    db.run(schema);

    writeln("Foo count: ", db.count!Foo.run);
    writeln("Bar count: ", db.count!Bar.run);

    foreach (v; db.select!Foo.where("text =", "hello").run)
        writeln(v);
    writeln;
    foreach (v; db.select!Bar.where("value <", 3).run)
        writeln(v);

    db.del!Foo.where("ts <", cts - cast(ulong) 1e8).run;

    db.insert(Foo(0, "hello", cts), Foo(20, "world", cts));
    db.insert(Foo(0, "hello", cts), Foo(0, "world", cts));
    import std.random : uniform;

    db.insert(Bar(0, uniform(0, 10), Baz("one", 3.14)));

    db.insertOrReplace(Foo(1, "hello", cts), Foo(3, "world", cts));
}
