/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.utility;

/** Convert a string to the "real path" by resolving all symlinks resulting in an absolute path.

TODO: optimize
This function is very inefficient. It creates a lot of GC garbage.
It should also be moved to source/dextool in the future to be able to be re-used by other components.
Maybe even integrated in AbsolutePath.

trusted: orig_p is a string. A string is assured by the language to be memory
safe. Thus this function that operates on strings as input are memory safe for
all possible input.
  */
string toRealPath(const string orig_p) @trusted {
    import core.sys.posix.stdlib : realpath;
    import core.stdc.stdlib : free;
    import std.string : toStringz, fromStringz;

    auto p = orig_p.toStringz;
    auto absp = realpath(p, null);
    scope (exit) {
        if (absp)
            free(absp);
    }

    if (absp is null)
        return orig_p;
    else
        return absp.fromStringz.idup;
}
