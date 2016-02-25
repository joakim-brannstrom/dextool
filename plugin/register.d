// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.register;

import std.typecons : Typedef;

public import plugin.types;

private shared(Plugin[]) plugins;

/** Plugin registration.
 * Params:
 *  category = main category of the plugin, e.g cpptestdouble
 *  info = oneliner information about the category
 *  opts = tuple with usage, optional and others
 *  func = callback function
 *
 * Example:
 * ----
 * plugin/frontend/cpptestdouble.d
 * ----
 */
void registerPlugin(CliCategory category, CliCategoryInfo info,
        CliOptionParts opts, PluginFuncType func) {
    plugins ~= Plugin(category, info, opts, func);
}

/// Only for internal usage.
Plugin[] getRegisteredPlugins() {
    return cast(Plugin[]) plugins;
}
