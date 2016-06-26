// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Various utilities used by generators.
*/
module cpptooling.generator.utility;

import std.functional : unaryFun;
import std.traits;
import std.range : ElementType;

template validLocation(alias predicate) if (is(typeof(unaryFun!predicate))) {
    auto validLocation(Loc)(Loc loc) {
        import std.algorithm : filter, map;
        import std.range : only;
        import cpptooling.data.type : LocationTag, Location;

        // dfmt off
        return only(loc)
            // remove invalid locations
            .filter!(a => a.kind != LocationTag.Kind.noloc)
            // convert to the desired type
            .map!(a => cast(Location) a)
            // filter out those that the user do not want
            .filter!(a => unaryFun!predicate(a));
        // dfmt on
    }
}

template storeValidLocations(alias storeFun) if (is(typeof(unaryFun!storeFun))) {
    auto storeValidLocations(Range)(Range range) {
        import std.algorithm : each;
        import std.range : tee;
        import cpptooling.data.type : LocationTag, Location;

        static if (hasMember!(ElementType!(Range), "locations")) {
            return range.tee!(a => a.locations.validLocations!(a => true).each!(a => storeFun(a)));
        } else {
            return range.tee!((a) {
                if (a.location.kind != LocationTag.Kind.noloc) {
                    storeFun(a.location);
                }
            });
        }
    }
}

template filterAnyLocation(alias predicate) if (is(typeof(unaryFun!predicate))) {
    auto filterAnyLocation(Range)(Range range) {
        import std.algorithm : filter, any;
        import cpptooling.data.type : LocationTag, Location;

        bool anyLocation(T)(T value, LocationTag loc) {
            final switch (loc.kind) {
            case LocationTag.Kind.noloc:
                return false;
            case LocationTag.Kind.loc:
                return predicate(value, cast(Location) loc);
            }
        }

        static if (hasMember!(ElementType!(Range), "locations")) {
            return range.filter!(a => a.locations.any!(loc => anyLocation(a, loc)));
        } else {
            return range.filter!(a => anyLocation(a, a.location));
        }
    }
}
