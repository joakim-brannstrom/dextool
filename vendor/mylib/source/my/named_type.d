/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This is inspired from [NamedTypes C++](https://github.com/joboccara/NamedType).

A strong type is a type used in place of another type to carry specific meaning
through its name. It is a variant of `TypeDef` in phobos

## Basic usage

The central piece is the templated class NamedType, which can be used to declare
a strong type with a typedef-like syntax:

```d
alias Width = NamedType!(double, Tag!"width");
alias Height = NamedType!(double, Tag!"height");
```

which can be used to make interfaces more expressive and more robust. Note how
the below constructor shows in which order it expects its parameters:

```d
class Rectangle {
    private double width_;
    private double height_;

    this(Width width, Height height) {
        this.width_ = width.get;
        this.height_ = height.get;
    }

    double width() const { return width_; }
    double height() const { return height_; }
}
```

**Strong types are about better expressing your intentions, both to the
compiler and to other human developers.**

## Strong typing over generic types

This implementation of strong types can be used to add strong typing over
generic or unknown types such as lambdas:

```d
static bool performAction(T)(T x, T y) if(hasTraits!(T, Comparable)) {
    return x > y;
}
```

## Inheriting the underlying type functionalities

You can declare which functionalities should be inherited from the underlying
type. So far, only basic operators are taken into account. For instance, to
inherit from `+` and `toString`, you can declare the strong type:

```d
alias Meter = NamedType!(double, Tag!"meter", Addable, Printable);
```

There is one special trait, `ImplicitConvertable`, that lets the strong type be
converted in the underlying type. This has the effect of removing the need to
call .get() to get the underlying value.

## Named arguments

By their nature strong types can play the role of named parameters:

```d
alias FirstName = NamedType!(string, Tag!"firstName");
alias LastName = NamedType!(string, Tag!"lastName");

void displayName(FirstName theFirstName, LastName theLastName);

// Call site
displayName(FirstName("John"), LastName("Doe"));
```

But the nested type `argument` allows to emulate a named argument syntax:

```d
alias FirstName = NamedType!(string, Tag!"firstName");
alias LastName = NamedType!(string, Tag!"lastName");

void displayName(FirstName theFirstName, LastName theLastName);

// Call site
displayName(FirstName.argument = "John", LastName.argument = "Doe");
```
*/
module my.named_type;

struct Tag(alias T) {
    static string toString() {
        static if (is(typeof(T) : string))
            return T;
        else
            return T.stringof;
    }
}

alias NamedTypeT(T, Traits...) = NamedType!(T, Tag!(T.stringof), T.init, Traits);

enum hasTraits(T, Traits...) = is(T.Traits == Traits);

struct NamedType(T, TagT = Tag!(T.stringof), T init = T.init, TraitsT...)
        if (is(TagT : Tag!U, alias U)) {
    import std.meta : staticMap, AliasSeq;
    import std.range : isOutputRange;

    /// The underlying type.
    alias Type = T;
    alias Traits = TraitsT;
    alias Tag = TagT;
    alias ThisT = typeof(this);

    private T value = init;

    // https://issues.dlang.org/show_bug.cgi?id=18415
    // prevent default construction if original type does too.
    static if ((is(T == struct) || is(T == union)) && !is(typeof({ T t; }))) {
        @disable this();
    }

    this(T v) {
        this.value = v;
    }

    this(NamedType!(T, Tag, init, Traits) v) {
        this.value = v.value;
    }

    T opCast(T2 : T)() inout {
        return value;
    }

    /// The underlying value.
    ref inout(T) get() inout {
        return value;
    }

    /// Useful for e.g. getopt integration
    scope T* getPtr() {
        return &value;
    }

    static typeof(this) make(T v) {
        return typeof(this)(v);
    }

    private static struct EmulateNamedArgument {
        ThisT value;
        alias value this;
    }

    static EmulateNamedArgument argument(T value) {
        return EmulateNamedArgument(ThisT(value));
    }

    template ReplaceTrait(T) {
        static if (is(T == Arithmetic)) {
            alias ReplaceTrait = AliasSeq!(Incrementable, Decrementable, Addable,
                    Subtractable, Modulable, Divisable, Multiplicable, Printable, Comparable);
        } else {
            alias ReplaceTrait = T;
        }
    }

    static foreach (Tr; staticMap!(ReplaceTrait, Traits)) {
        //pragma(msg, Tr);
        static if (is(Tr == Comparable)) {
            bool opEquals(const typeof(this) rhs) inout {
                return value == rhs.value;
            }

            bool opEquals(ref const typeof(this) rhs) inout {
                return value == rhs.value;
            }

            int opCmp(ref const typeof(this) rhs) const {
                // return -1 if "this" is less than rhs, 1 if bigger and zero
                // equal.
                if (value < rhs.value)
                    return -1;
                if (value > rhs.value)
                    return 1;
                return 0;
            }
        } else static if (is(Tr == Hashable)) {
            static if (__traits(hasMember, T, "toHash")) {
                size_t toHash(T2 = typeof(this))() {
                    return value.toHash;
                }
            } else {
                size_t toHash() @safe nothrow const scope {
                    return typeid(value).getHash(&value);
                }
            }
        } else static if (is(Tr == Incrementable)) {
            auto opUnary(string op)() if (op == "++") {
                return typeof(this)(++value);
            }
        } else static if (is(Tr == Decrementable)) {
            auto opUnary(string op)() if (op == "--") {
                return typeof(this)(--value);
            }
        } else static if (is(Tr == Addable)) {
            auto opBinary(string op)(typeof(this) rhs) if (op == "+") {
                return typeof(this)(value + rhs.value);
            }
        } else static if (is(Tr == Subtractable)) {
            auto opBinary(string op)(typeof(this) rhs) if (op == "-") {
                return typeof(this)(value - rhs.value);
            }
        } else static if (is(Tr == Modulable)) {
            auto opBinary(string op)(typeof(this) rhs) if (op == "%") {
                return typeof(this)(value % rhs.value);
            }
        } else static if (is(Tr == Divisable)) {
            auto opBinary(string op)(typeof(this) rhs) if (op == "/") {
                return typeof(this)(value / rhs.value);
            }
        } else static if (is(Tr == Multiplicable)) {
            auto opBinary(string op)(typeof(this) rhs) if (op == "*") {
                return typeof(this)(value * rhs.value);
            }
        } else static if (is(Tr == ImplicitConvertable)) {
            alias get this;
        } else static if (is(Tr == Printable)) {
            import std.format : singleSpec, FormatSpec, formatValue;

            string toString(T2 = typeof(this))() {
                import std.array : appender;

                auto buf = appender!string;
                auto spec = singleSpec("%s");
                toString(buf, spec);
                return buf.data;
            }

            void toString(Writer, T2 = typeof(this))(ref Writer w, scope const ref FormatSpec!char fmt)
                    if (isOutputRange!(Writer, char)) {
                import std.range : put;

                put(w, Tag.toString);
                put(w, "(");
                formatValue(w, value, fmt);
                put(w, ")");
            }
        } else {
            static assert(0, "Unknown trait " ~ Tr.stringof);
        }
    }
}

struct Comparable {
}

struct Incrementable {
}

struct Decrementable {
}

struct Addable {
}

struct Subtractable {
}

struct Modulable {
}

struct Divisable {
}

struct Multiplicable {
}

struct Printable {
}

struct ImplicitConvertable {
}

struct Hashable {
}

struct Arithmetic {
}

@("shall be possible to use a NamedType to express the intent of parameters")
unittest {
    alias Width = NamedType!(double, Tag!"width");
    alias Height = NamedType!(double, Tag!"height");

    static void calcSquare(Width w, Height h) {
        assert(w.get * h.get > w.get);
    }

    calcSquare(Width(42), Height(84));
}

@("shall be possible to cast to the underlying type")
unittest {
    auto x = NamedType!(int, Tag!"x")(42);
    assert(cast(int) x == 42);
}

@("shall implement the compare operators")
unittest {
    alias A = NamedType!(int, Tag!"x", 0, Comparable);
    auto x = A(42);
    auto y = A(84);
    assert(x == x);
    assert(x != y);
    assert(x < y);
    assert(y > x);
}

@("shall implement the arithmetic operators")
unittest {
    alias A = NamedType!(int, Tag!"x", 0, Arithmetic);
    auto x = A(10);
    auto y = A(20);
    assert(++A(x)++ == A(11));
    assert(--A(x)-- == A(9));

    assert(x + x == A(20));
    assert(x + y == A(30));
    assert(x - y == A(-10));
    assert(y / x == A(2));
    assert(y * x == A(200));
    assert(x % y == A(10));
    assert(x.toString == "x(10)");
}

@("shall implement a function that take a type that implement the Comparable trait")
unittest {
    static bool perform(T)(T x, T y) if (hasTraits!(T, Comparable)) {
        return x > y;
    }

    alias A = NamedTypeT!(int, Comparable);
    assert(perform(A(20), A(10)));
}

@("shall add implicit convertable")
unittest {
    alias A = NamedTypeT!(int, ImplicitConvertable);
    auto x = A(10);
    assert(x == 10);
}

@("shall emulate named arguments syntax")
unittest {
    alias A = NamedTypeT!(int);
    static bool fun(A x) {
        return true;
    }

    assert(fun(A.argument = 10));
}

@("shall be possible to use in an AA")
unittest {
    alias A = NamedType!(long, Tag!"A", 0, Comparable, Hashable);
    A[A] x;
    x[A(10)] = A(20);
    assert(x[A(10)] == A(20));
}

@("shall be possible to cast to the underlying type")
unittest {
    alias A = NamedTypeT!(int);
    auto a = A(10);
    const b = A(20);
    assert(10 == cast(int) a);
    assert(20 == cast(int) b);
}

@("shall be possible to call get of a const instance")
unittest {
    alias A = NamedTypeT!(int);
    const b = A(20);
    assert(20 == b.get);
}

@("shall only use the Tag when printing")
unittest {
    import std.format : format;

    alias A = NamedTypeT!(int, Printable);
    auto s = format!"value is %s"(A(10));
    assert(s == "value is int(10)");
}
