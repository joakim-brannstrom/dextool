/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.ctestdouble.frontend.types;

/// A symbol to filter. How it is used is handled by the query function.
struct FilterSymbol {
@safe:

    private bool[string] filter;
    private bool has_symbols;

    bool contains(string symbol) {
        if (symbol in filter)
            return true;
        return false;
    }

    bool hasSymbols() {
        return has_symbols;
    }

    void put(string symbol) {
        has_symbols = true;
        filter[symbol] = true;
    }

    auto range() @trusted {
        return filter.byKeyValue();
    }
}
