/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.stub.convert;

import std.array : join;
import logger = std.experimental.logger;

import clang.Cursor;

import translator.Type : TypeKind, translateType;

import generator.stub.types;

/// Convert a vector of TypeName to string pairs.
auto toStrings(const TypeName[] vars) pure @safe nothrow {
    import std.algorithm : map;
    import std.array : array;

    string[] params = vars.map!(tn => cast(string) tn.type ~ " " ~ cast(string) tn.name).array;

    return params;
}

/// Convert a vector of TypeName to a comma separated string.
auto toString(const TypeName[] vars) pure @safe nothrow {
    auto params = vars.toStrings;
    return join(params, ", ");
}

/// Convert a vector of TypeKindVariable to an underscore separated string of types.
///TODO cleanup the implementation. Ugly...
auto toStringOfType(const TypeKindVariable[] vars) pure @safe nothrow {
    import std.algorithm : map;
    import std.array : join, appender;
    import std.string : replace;
    import std.range : retro;

    static auto ifConst(T)(T a) {
        return a.type.isConst ? "const" : "";
    }

    // convert *& to string representation
    static string helper(T)(T a) {
        auto app = appender!string();
        foreach (l; a.type.toString) {
            switch (l) {
            case '&':
                app.put("Ref");
                break;
            case '*':
                app.put("Ptr");
                break;
            default:
            }
        }

        return app.data;
    }

    string rval = vars.map!(a => "_" ~ ifConst(a) ~ a.type.name.replace(" ", "") ~ helper(a)).join(
        "").replace(" ", "_");
    return rval;
}

/// Convert a vector of TypeKindVariable to a comma separated string of parameters.
auto toStringOfName(const TypeKindVariable[] vars) {
    import std.algorithm : map;
    import std.array : join;

    return vars.map!(a => cast(string) a.name).join(", ");
}

/// Convert a vector of TypeKindVariable to a comma separated string of types, aka a parameter list.
auto toParamString(const TypeKindVariable[] vars) {
    import std.algorithm : map;
    import std.array : join;

    return vars.map!(a => a.type.toString ~ " " ~ a.name.str).join(", ");
}
