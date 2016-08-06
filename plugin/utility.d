// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Utility useful for plugins.
*/
module plugin.utility;

/** Make a static c'tor that creates an instance with all class members initialized.
 *
 * Params:
 *   T = type to construct an instance of
 *   postInit = call the function with the initialized instance.
 */
mixin template MakerInitializingClassMembers(T, alias postInit = function void(ref T) {
}) {
    static T make() {
        T inst;

        foreach (member; __traits(allMembers, T)) {
            alias MemberT = typeof(__traits(getMember, inst, member));
            static if (is(MemberT == class)) {
                __traits(getMember, inst, member) = new MemberT;
            }
        }

        postInit(inst);

        return inst;
    }
}
