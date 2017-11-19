/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Various utilities used by generators.
TODO change the name of this module to location_filter.
*/
module cpptooling.generator.utility;

import std.functional : unaryFun;
import std.traits;
import std.range : ElementType;

version (unittest) {
    import unit_threaded : shouldEqual;
}

/** Filter according to location existence and predicate.
 *
 * A false result is:
 *  - neither a location for a declaration or definition exist.
 *  - fails the predicate.
 *
 * The predicate is only called when a location exist.
 */
template filterAnyLocation(alias predicate) {
    alias predFun = unaryFun!predicate;

    auto filterAnyLocation(Range, LookupT)(Range range, LookupT lookup) {
        import std.algorithm : filter, map;
        import std.typecons : tuple;
        import std.range : ElementType;
        import cpptooling.data.type : LocationTag, Location;

        struct LocElem {
            LocationTag location;
            ElementType!Range value;
        }

        // dfmt off
        return range
            // get the location associated with each item
            .map!(a => tuple(lookup(a.usr), a))
            // remove those that don't have a location
            .filter!(a => a[0].length != 0)
            // unpack the location. a declaration or definition, doesn't matter
            .map!(a => tuple(a[0].front.any, a[1]))
            // pack data in a struct that make it easier to use with named
            // fields
            .map!(a => LocElem(a[0].front, a[1]))
            .filter!(a => predicate(a));
        // dfmt on
    }
}

@("shall only let USRs with a location pass")
unittest {
    import std.algorithm : joiner;
    import std.array : array;
    import std.range : only, dropOne;
    import std.typecons : Nullable;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.data.type : LocationTag, Location;

    auto valid_loc = LocationTag(Location("valid.h", 1, 2));

    static struct ImplAny {
        Nullable!LocationTag data;

        static auto makeNull() {
            auto rval = ImplAny(LocationTag.init);
            rval.data.nullify;
            return rval;
        }

        this(LocationTag data) {
            this.data = data;
        }

        auto any() {
            return data.isNull ? only(LocationTag.init).dropOne : only(data.get);
        }
    }

    static struct ImplUSR {
        USRType usr;
        int id; /// only for test purpose to ensure the data has passed through
    }

    // dfmt off
    // predicate says "yes", expecting meaning of life
    filterAnyLocation!(a => true)(
        only(ImplUSR(USRType("fool"), 42)), (USRType a) { return only(ImplAny(valid_loc)); } )
        .front.value.id.shouldEqual(42);

    // lookup says "no location for that USR", expecting filter to catch and remove the nothingness
    filterAnyLocation!(a => true)(
        only(ImplUSR(USRType("fool"), 42)), (USRType a) { return only(ImplAny.makeNull).dropOne; } )
        .array()
        .length.shouldEqual(0);

    // predicate says "no", expecting filter to remove the input
    filterAnyLocation!(a => false)(
        only(ImplUSR(USRType("fool"), 42)), (USRType a) { return only(ImplAny(valid_loc)); } )
        .array()
        .length.shouldEqual(0);

    // dfmt on
}
