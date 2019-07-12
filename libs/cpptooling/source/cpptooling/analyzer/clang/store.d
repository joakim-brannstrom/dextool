/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.store;

import dextool.nullable;

import clang.Cursor : Cursor;

import cpptooling.analyzer.clang.type : TypeResults;
import cpptooling.data.symbol : Container;

//TODO remove the default value for indent.
void put(ref Nullable!TypeResults tr, ref Container container, in uint indent = 0) @safe {
    import std.range : chain, only;

    if (tr.isNull) {
        return;
    }

    foreach (a; chain(only(tr.primary), tr.extra)) {
        container.put(a.type.kind);
        container.put(a.location, a.type.kind.usr, a.type.attr.isDefinition);
    }
}
