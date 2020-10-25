/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.random;

/// Returns: a random string of `length` letters.
string randomId(int length) {
    import std.ascii : letters;
    import std.conv : to;
    import std.random : randomCover, randomSample;
    import std.utf : byCodeUnit;

    return letters.byCodeUnit.randomCover.randomSample(length).to!string;
}

@("shall produce a random id as a string")
unittest {
    import std.algorithm : map, sort;
    import std.array : array;
    import std.range : iota;

    auto id = iota(0, 10).map!(a => randomId(30)[0 .. 3]).array.sort.array;
    // previously there was a bug where the first three letters had a high
    // probability of being the same.
    assert(id[0] != id[1] && id[1] != id[2]);
}
