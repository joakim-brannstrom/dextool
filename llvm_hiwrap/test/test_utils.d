/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module test_utils;

string removeComments(string txt) {
    import std.algorithm : splitter, filter, joiner;
    import std.array : array;
    import std.ascii : newline;
    import std.exception : assumeUnique;
    import std.string : startsWith;
    import std.utf : byChar;

    // dfmt off
    return txt
        .splitter(newline)
        .filter!(a => !a.startsWith(";"))
        .joiner(newline)
        .byChar
        .array()
        .assumeUnique;
    // dfmt on
}
