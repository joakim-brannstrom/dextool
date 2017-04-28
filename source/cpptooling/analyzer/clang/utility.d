/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.utility;

import std.typecons : Nullable;

import clang.Cursor : Cursor;

import cpptooling.analyzer.clang.type : TypeResults;
import cpptooling.data.symbol.container : Container;

deprecated("Slated for removal 2017-05-30. Use cpptooling.analyzer.clang.store : put instead") void put(
        ref Nullable!TypeResults tr, ref Container container, in uint indent = 0) @safe {
    static import cpptooling.analyzer.clang.store;

    cpptooling.analyzer.clang.store.put(tr, container, indent);
}
