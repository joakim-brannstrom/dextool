sumtype
=======

A sum type for modern D.

Features
--------

- Pattern matching, including support for structural matching
- Self-referential types, using `This`
- Works with `pure`, `@safe`, `@nogc`, `nothrow`, and `immutable`
- Zero runtime overhead compared to hand-written C
    - No heap allocation
    - Does not rely on runtime type information (`TypeInfo`)

Documentation
-------------

[View online on Github Pages.][docs]

`sumtype` uses [adrdox][] to generate its documentation. To build your own
copy, run the following command from the root of the `sumtype` repository:

    path/to/adrdox/doc2 --genSearchIndex --genSource -o generated-docs src

[docs]: https://pbackus.github.io/sumtype/sumtype.html
[adrdox]: https://github.com/adamdruppe/adrdox

Example
-------

    import std.math: approxEqual, cos, PI, sqrt;

    struct Rectangular { double x, y; }
    struct Polar { double r, theta; }
    alias Vector = SumType!(Rectangular, Polar);

    pure @safe @nogc nothrow
    double length(Vector v)
    {
        return v.match!(
            rect => sqrt(rect.x^^2 + rect.y^^2),
            polar => polar.r
        );
    }

    pure @safe @nogc nothrow
    double horiz(Vector v)
    {
        return v.match!(
            rect => rect.x,
            polar => polar.r * cos(polar.theta)
        );
    }

    Vector u = Rectangular(1, 1);
    Vector v = Polar(1, PI/4);

    assert(length(u).approxEqual(sqrt(2.0)));
    assert(length(v).approxEqual(1));
    assert(horiz(u).approxEqual(1));
    assert(horiz(v).approxEqual(sqrt(0.5)));

[![Open on run.dlang.io](https://img.shields.io/badge/run.dlang.io-open-blue.svg)](https://run.dlang.io/is/X4jUxq)

Installation
------------

If you're using dub, add the [sumtype](https://code.dlang.org/packages/sumtype)
package to your project as a dependency.

Alternatively, since it's a single, self-contained module, you can simply copy
`sumtype.d` to your source directory and compile as usual.
