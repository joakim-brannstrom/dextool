// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

TODO remove the trailing s in the module name, ....symbol.types <---
*/
module cpptooling.data.symbol.types;

/** The type of C++ symbol that is referenced.
 * The class must exist.
 */
enum Kind {
    None,
    TypeKind,
    CppClass
}

struct FullyQualifiedNameType {
    string payload;
    alias payload this;
}

struct USRType {
    string payload;
    alias payload this;
}
