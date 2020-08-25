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
    import std.random : randomSample;
    import std.utf : byCodeUnit;

    return letters.byCodeUnit.randomSample(length).to!string;
}
