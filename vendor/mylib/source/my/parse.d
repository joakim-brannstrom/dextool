/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.parse;

import core.time : Duration, dur;

class TimeParseException : Exception {
    this(string msg) @safe {
        super(msg);
    }
}

/** Parse a string as a duration.
 *
 * Example:
 * ---
 * auto d = parseDuration("1 hours 2 minutes");
 * ---
 *
 * Params:
 *  timeSpec = string to parse
 *
 * Returns: a `Duration`
 *
 * Throws: `TimeParseException` if unable to parse the string.
 */
Duration parseDuration(string timeSpec) @safe {
    import std.conv : to;
    import std.format : format;
    import std.range : chunks;
    import std.string : split;

    Duration d;
    const parts = timeSpec.split;

    if (parts.length % 2 != 0) {
        throw new TimeParseException("Invalid time specification. The format is: value unit");
    }

    foreach (const p; parts.chunks(2)) {
        const nr = p[0].to!long;
        bool validUnit;
        immutable Units = [
            "msecs", "seconds", "minutes", "hours", "days", "weeks"
        ];
        static foreach (Unit; Units) {
            if (p[1] == Unit) {
                d += nr.dur!Unit;
                validUnit = true;
            }
        }
        if (!validUnit) {
            throw new Exception(format!"Invalid unit '%s'. Valid are %-(%s, %)."(p[1], Units));
        }
    }

    return d;
}

@("shall parse a string to a duration")
unittest {
    const expected = 1.dur!"weeks" + 1.dur!"days" + 3.dur!"hours"
        + 2.dur!"minutes" + 5.dur!"seconds" + 9.dur!"msecs";
    const d = parseDuration("1 weeks 1 days 3 hours 2 minutes 5 seconds 9 msecs");
    assert(d == expected);
}
