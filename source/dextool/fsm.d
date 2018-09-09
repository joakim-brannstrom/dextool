/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains utilities to reduce the boilerplate when implementing a
FSM.
*/
module dextool.fsm;

/** Generate a mixin of a callback for each literal in `Action`.
 *
 * Example:
 * ---
 * enum MyAct { foo }
 * mixin(generateActions!MyAct("act", "obj"));
 * // generates a callback such as this
 * obj.act_foo();
 * ---
 *
 * Params:
 *  varName = name of the variable to read the action from.
 *  objVar = object to do the callbacks on.
 *  prefix = prefix all callbacks with this string
 */
string generateActions(ActionT, string actVar, string objVar, string prefix = null,
        string File = __FILE__, int Line = __LINE__)() {
    import std.conv : to;
    import std.format : format;
    import std.traits : EnumMembers;

    string s = format("final switch(%s) {", actVar);
    static foreach (a; EnumMembers!ActionT) {
        {
            const actfn = format("%s%s", prefix, a);
            s ~= format("case %s.%s: %s.%s();break;", ActionT.stringof, a, objVar, actfn);
            s ~= "\n";
        }
    }
    s ~= "}";

    return s;
}
