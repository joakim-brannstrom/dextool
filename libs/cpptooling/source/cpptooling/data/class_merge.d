/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.data.class_merge;

import cpptooling.data.representation : CppClass;
import cpptooling.data.symbol : Container;
import cpptooling.data.symbol.types : FullyQualifiedNameType;

import std.typecons : NullableRef;
import std.range : only;

@safe:

alias LookupT = typeof(only(NullableRef!(CppClass).init)) delegate(FullyQualifiedNameType a);

/** Create a merged class with methods from all those classes it inherits from.
 *
 * Params:
 *  LookupT = a callback that takes a FullyQualifiedNameType and returns a
 *      range with zero or one elements of type NullableRef!CppClass.
 */
CppClass mergeClassInherit(ref CppClass class_, ref Container container, LookupT lookup) {
    import std.algorithm : each;

    if (class_.inheritRange.length == 0) {
        return class_;
    }

    auto methods = dedup(getMethods(class_, container, lookup));

    auto c = CppClass(class_.name, class_.inherits, class_.resideInNs);
    () @trusted { methods.each!(a => c.put(a)); }();

    return c;
}

private:

bool isMethodOrOperator(T)(T method) @trusted {
    import std.variant : visit;
    import cpptooling.data.representation : CppMethod, CppMethodOp, CppCtor, CppDtor;

    // dfmt off
    return method.visit!((CppMethod a) => true,
                         (CppMethodOp a) => true,
                         (CppCtor a) => false,
                         (CppDtor a) => false);
    // dfmt on
}

CppClass.CppFunc[] getMethods(ref CppClass c, ref Container container, LookupT lookup) @safe {
    import std.array : array, appender;
    import std.algorithm : cache, copy, each, filter, joiner, map;
    import std.range : chain;

    // dfmt off
    auto local_methods = c.methodRange
        .filter!(a => isMethodOrOperator(a));

    auto inherit_methods = c.inheritRange
        .map!(a => lookup(a.fullyQualifiedName))
        // some classes do not exist in AST thus no methods returned
        .joiner
        .map!(a => getMethods(a, container, lookup));
    // dfmt on

    auto methods = appender!(CppClass.CppFunc[])();
    () @trusted { local_methods.copy(methods); inherit_methods.copy(methods); }();

    return methods.data;
}

//TODO this function is inefficient. So many allocations...
auto dedup(CppClass.CppFunc[] methods) @trusted {
    import std.array : array;
    import std.algorithm : makeIndex, uniq, map, sort;
    import cpptooling.utility.dedup : dedup;
    import cpptooling.data.representation : funcToString;

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

    //TODO inefficient, lots of intermittent arrays and allocations.
    // Convert to a range based no-allocation.

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
