/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.cpptestdouble.backend.class_merge;

import cpptooling.data : CppClass;
import cpptooling.data.symbol : Container;

import dextool.plugin.cpptestdouble.backend.type : ImplData;

@safe:

CppClass mergeClassInherit(ref CppClass class_, ref Container container, ref ImplData impl) {
    if (class_.inheritRange.length == 0) {
        return class_;
    }

    //TODO inefficient, lots of intermittent arrays and allocations.
    // Convert to a range based no-allocation.

    static bool isMethodOrOperator(T)(T method) @trusted {
        import std.variant : visit;
        import cpptooling.data : CppMethod, CppMethodOp, CppCtor, CppDtor;

        // dfmt off
        return method.visit!((const CppMethod a) => true,
                        (const CppMethodOp a) => true,
                        (const CppCtor a) => false,
                        (const CppDtor a) => false);
        // dfmt on
    }

    static CppClass.CppFunc[] getMethods(const ref CppClass c,
            ref Container container, ref ImplData impl) @safe {
        import std.array : array, appender;
        import std.algorithm : cache, copy, each, filter, joiner, map;
        import std.range : chain;

        // dfmt off
        auto local_methods = c.methodRange
                .filter!(a => isMethodOrOperator(a));

        auto inherit_methods = c.inheritRange
            .map!(a => impl.lookupClass(a.fullyQualifiedName))
            // some classes do not exist in AST thus no methods returned
            .joiner
            .map!(a => getMethods(a, container, impl));
        // dfmt on

        auto methods = appender!(CppClass.CppFunc[])();
        () @trusted{ local_methods.copy(methods); inherit_methods.copy(methods); }();

        return methods.data;
    }

    //TODO this function is inefficient. So many allocations...
    static auto dedup(CppClass.CppFunc[] methods) @trusted {
        import std.array : array;
        import std.algorithm : makeIndex, uniq, map, sort;
        import cpptooling.utility.dedup : dedup;
        import cpptooling.data : funcToString;

        static auto getUniqeId(T)(ref T method) {
            import std.variant : visit;
            import cpptooling.data : CppMethod, CppMethodOp, CppCtor, CppDtor;

            // dfmt off
            return method.visit!((CppMethod a) => a.id,
                                 (CppMethodOp a) => a.id,
                                 (CppCtor a) => a.id,
                                 (CppDtor a) => a.id);
            // dfmt on
        }

        auto arr = methods.map!(a => getUniqeId(a)).array();

        auto index = new size_t[arr.length];
        // sorting the indexes
        makeIndex(arr, index);

        // dfmt off
        // contains a list of indexes into methods
        auto deduped_methods =
            index
            // dedup the sorted index
            .uniq!((a,b) => arr[a] == arr[b])
            .array();

        // deterministic sorting by function signature
        deduped_methods.sort!((a,b) { return methods[a].funcToString < methods[b].funcToString; });

        return deduped_methods
            // reconstruct an array from the sorted indexes
            .map!(a => methods[a])
            .array();
        // dfmt on
    }

    auto methods = dedup(getMethods(class_, container, impl));

    auto c = CppClass(class_.name, class_.inherits, class_.resideInNs);
    // dfmt off
    () @trusted {
        import std.algorithm : each;
        methods.each!(a => c.put(a));
    }();
    // dfmt on

    return c;
}
