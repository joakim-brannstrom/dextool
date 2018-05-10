/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains helper functions for matching with regex.
*/
module dextool.plugin.regex_matchers;

import std.regex : Regex;

/// Returns: true if the value match any regex.
bool matchAny(const string value, Regex!char[] re) @safe nothrow {
    import std.algorithm : canFind;
    import std.regex : matchFirst, RegexException;

    bool passed = false;

    foreach (ref a; re) {
        try {
            auto m = matchFirst(value, a);
            if (!m.empty && m.pre.length == 0 && m.post.length == 0) {
                passed = true;
                break;
            }
        } catch (RegexException ex) {
        } catch (Exception ex) {
        }
    }

    return passed;
}

version (unittest) {
    import unit_threaded : shouldBeTrue;
}

@("Shall match all regex")
@safe unittest {
    import std.regex : regex;

    Regex!char[] re = [regex(".*/foo/.*"), regex(".*/src/.*")];

    matchAny("/p/foo/more/src/file.c", re).shouldBeTrue;
}
