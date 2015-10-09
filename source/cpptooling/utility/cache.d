// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/
module cpptooling.utility.cache;
import logger = std.experimental.logger;

/// Hold a cache of values to query for existance etc.
struct Cache(T) {
    private T[] values;

    void put(T v) {
        logger.trace(v);
        values ~= v;
    }

    bool exist(T v) @property {
        import std.algorithm : canFind;

        logger.trace(v);
        //return values.canFind(v);
        return false;
    }

    void clear() {
        values.length = 0;
    }
}
