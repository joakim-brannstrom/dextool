/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.filter;

@safe:

/** Filter strings by first cutting out a region (include) and then selectively
 * remove (exclude) from that region.
 *
 * I often use this in my programs to allow a user to specify what files to
 * process and the have some control over what to exclude.
 *
 * `--re-include` and `--re-exclude` is a suggestion for parameters to use with
 * `getopt`.
 */
struct ReFilter {
    import std.regex : Regex, regex, matchFirst;

    Regex!char includeRe;
    Regex!char[] excludeRe;

    /**
     * The regular expressions are set to ignoring the case.
     *
     * Params:
     *  include = regular expression.
     *  exclude = regular expression.
     */
    this(string include, string[] exclude) {
        includeRe = regex(include, "i");
        foreach (r; exclude)
            excludeRe ~= regex(r, "i");
    }

    /**
     * Returns: true if `s` matches `ìncludeRe` and NOT matches any of `excludeRe`.
     */
    bool match(string s) {
        if (matchFirst(s, includeRe).empty)
            return false;

        foreach (ref re; excludeRe) {
            if (!matchFirst(s, re).empty)
                return false;
        }

        return true;
    }
}

/// Example:
unittest {
    import std.algorithm : filter;
    import std.array : array;

    auto r = ReFilter("foo.*", [".*bar.*", ".*batman"]);

    assert(["foo", "foobar", "foo smurf batman", "batman", "fo",
            "foo mother"].filter!(a => r.match(a)).array == [
            "foo", "foo mother"
            ]);
}
