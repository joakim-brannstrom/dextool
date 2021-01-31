/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The purpose of this module is to allow you to segregate your `string` data that
represent a path from the rest. A string-that-is-a-type have specific
characteristics that we want to represent. This module have two types that help
you encode these characteristics.

This allows you to construct type safe APIs wherein a parameter that takes a
path can be assured that the data **actually** is a path. The API can further
e.g. require the parameter to be have the even higher restriction that it is an
absolute path.

I have found it extremely useful in my own programs to internally only work
with `AbsolutePath` types. There is a boundary in my programs that takes data
and converts it appropriately to `AbsolutePath`s. This is usually configuration
data, command line input, external libraries etc. This conversion layer handles
the defensive coding, validity checking etc that is needed of the data.

This has overall lead to a significant reduction in the number of bugs I have
had when handling paths and simplified the code. The program normally look
something like this:

* user input as raw strings via e.g. `getopt`.
* wrap path strings as either `Path` or `AbsolutePath`. Prefer `AbsolutePath`
  when applicable but there are cases where this is the wrong behavior. Lets
  say that the user input is relative to some working directory. Then later on
  in your program the two are combined to produce an `AbsolutePath`.
* internally in the program all parameters are `AbsolutePath`. A function that
  takes an `AbsolutePath` can be assured it is a path, full expanded and thus
  do not need any defensive code. It can use it as it is.

I have used an equivalent program structure when interacting with external
libraries.
*/
module my.path;

import std.range : isOutputRange, put;
import std.path : dirName, baseName, buildPath;

/** Types a string as a `Path` to provide path related operations.
 *
 * A `Path` is subtyped as a `string` in order to make it easy to integrate
 * with the Phobos APIs that take a `string` as an argument. Example:
 * ---
 * auto a = Path("foo");
 * writeln(exists(a));
 * ---
 */
struct Path {
    private string value_;

    alias value this;

    ///
    this(string s) @safe pure nothrow @nogc {
        value_ = s;
    }

    /// Returns: the underlying `string`.
    string value() @safe pure nothrow const @nogc {
        return value_;
    }

    ///
    bool empty() @safe pure nothrow const @nogc {
        return value_.length == 0;
    }

    ///
    size_t length() @safe pure nothrow const @nogc {
        return value_.length;
    }

    ///
    bool opEquals(const string s) @safe pure nothrow const @nogc {
        return value_ == s;
    }

    ///
    bool opEquals(const Path s) @safe pure nothrow const @nogc {
        return value_ == s.value_;
    }

    ///
    size_t toHash() @safe pure nothrow const @nogc scope {
        return value_.hashOf;
    }

    ///
    Path opBinary(string op)(string rhs) @safe const {
        static if (op == "~") {
            return Path(buildPath(value_, rhs));
        } else {
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
        }
    }

    ///
    inout(Path) opBinary(string op)(const Path rhs) @safe inout {
        static if (op == "~") {
            return Path(buildPath(value_, rhs.value));
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    ///
    void opOpAssign(string op)(string rhs) @safe nothrow {
        static if (op == "~=") {
            value_ = buldPath(value_, rhs);
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    void opOpAssign(string op)(const Path rhs) @safe nothrow {
        static if (op == "~=") {
            value_ = buildPath(value_, rhs);
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    ///
    T opCast(T : string)() const {
        return value_;
    }

    ///
    string toString() @safe pure nothrow const @nogc {
        return value_;
    }

    ///
    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        put(w, value_);
    }

    ///
    Path dirName() @safe const {
        return Path(value_.dirName);
    }

    ///
    string baseName() @safe const {
        return value_.baseName;
    }
}

/** The path is guaranteed to be the absolute, normalized and tilde expanded
 * path.
 *
 * An `AbsolutePath` is subtyped as a `Path` in order to make it easy to
 * integrate with the Phobos APIs that take a `string` as an argument. Example:
 * ---
 * auto a = AbsolutePath("foo");
 * writeln(exists(a));
 * ---
 *
 * The type is optimized such that it avoids expensive operations when it is
 * either constructed or assigned to from an `AbsolutePath`.
 */
struct AbsolutePath {
    import std.path : buildNormalizedPath, absolutePath, expandTilde;

    private Path value_;

    alias value this;

    ///
    this(string p) @safe {
        this(Path(p));
    }

    ///
    this(Path p) @safe {
        value_ = Path(p.value_.expandTilde.absolutePath.buildNormalizedPath);
    }

    ///
    bool empty() @safe pure nothrow const @nogc {
        return value_.length == 0;
    }

    /// Returns: the underlying `Path`.
    Path value() @safe pure nothrow const @nogc {
        return value_;
    }

    size_t length() @safe pure nothrow const @nogc {
        return value.length;
    }

    ///
    void opAssign(AbsolutePath p) @safe pure nothrow @nogc {
        value_ = p.value_;
    }

    ///
    void opAssign(Path p) @safe {
        value_ = p.AbsolutePath.value_;
    }

    ///
    Path opBinary(string op, T)(T rhs) @safe if (is(T == string) || is(T == Path)) {
        static if (op == "~") {
            return value_ ~ rhs;
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    ///
    void opOpAssign(string op)(T rhs) @safe if (is(T == string) || is(T == Path)) {
        static if (op == "~=") {
            value_ = AbsolutePath(value_ ~ rhs).value_;
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    ///
    string opCast(T : string)() pure nothrow const @nogc {
        return value_;
    }

    ///
    Path opCast(T : Path)() pure nothrow const @nogc {
        return value_;
    }

    ///
    bool opEquals(const string s) @safe pure nothrow const @nogc {
        return value_ == s;
    }

    ///
    bool opEquals(const Path s) @safe pure nothrow const @nogc {
        return value_ == s.value_;
    }

    ///
    bool opEquals(const AbsolutePath s) @safe pure nothrow const @nogc {
        return value_ == s.value_;
    }

    ///
    string toString() @safe pure nothrow const @nogc {
        return cast(string) value_;
    }

    ///
    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        put(w, value_);
    }

    ///
    AbsolutePath dirName() @safe const {
        // avoid the expensive expansions and normalizations.
        AbsolutePath a;
        a.value_ = value_.dirName;
        return a;
    }

    ///
    Path baseName() @safe const {
        return value_.baseName.Path;
    }
}

@("shall always be the absolute path")
unittest {
    import std.algorithm : canFind;
    import std.path;

    assert(!AbsolutePath(Path("~/foo")).toString.canFind('~'));
    assert(AbsolutePath(Path("foo")).toString.isAbsolute);
}

@("shall expand . without any trailing /.")
unittest {
    import std.algorithm : canFind;

    assert(!AbsolutePath(Path(".")).toString.canFind('.'));
    assert(!AbsolutePath(Path(".")).toString.canFind('.'));
}

@("shall create a compile time Path")
unittest {
    enum a = Path("A");
}

@("shall subtype to a string")
unittest {
    string a = Path("a");
    string b = AbsolutePath(Path("a"));
}

@("shall build path from path ~ string")
unittest {
    import std.file : getcwd;
    import std.meta : AliasSeq;
    import std.stdio;

    static foreach (T; AliasSeq!(string, Path)) {
        {
            const a = Path("foo");
            const T b = "smurf";
            Path c = a ~ b;
            assert(c.value == "foo/smurf");
        }
    }

    static foreach (T; AliasSeq!(string, Path)) {
        {
            const a = Path("foo");
            const T b = "smurf";
            AbsolutePath c = a ~ b;
            assert(c.value.value == buildPath(getcwd, "foo", "smurf"));
        }
    }
}
