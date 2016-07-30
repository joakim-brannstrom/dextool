/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.docopt_util;

import logger = std.experimental.logger;

import docopt : ArgValue;

/** Correctly log all type of messages via logger.
 *
 * docopt uses std.json internally for pretty printing which results in errors
 * for regex containing things like "\.".
 */
void printArgs(ref ArgValue[string] parsed) nothrow {
    import std.algorithm : map, joiner;
    import std.ascii : newline;
    import std.conv : text;
    import std.format : format;
    import std.string : leftJustifier;

    bool err = true;

    try {
        // dfmt off
        logger.trace("args:",
                newline,
                parsed.byKeyValue()
                    .map!(a => format("%s:%s", leftJustifier(a.key, 20), a.value.toString))
                    .joiner(newline).text()
               );
        // dfmt on
        err = false;
    }
    catch (Exception ex) {
        ///TODO change to the specific exceptions.
    }

    if (err) {
        try {
            logger.error("Unable to log parsed program arguments");
        }
        catch (Exception ex) {
        }
    }
}
