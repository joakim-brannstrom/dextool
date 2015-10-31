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
module analyze.wip;

import std.typecons;

import tested;

import translator.Type : TypeKind;

alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppClassName = Typedef!(string, string.init, "CppClassName");
alias CppVariable = Typedef!(string, string.init, "CppVariable");

alias TypeKindVariable = Tuple!(TypeKind, "type", CppVariable, "name");

pure @safe nothrow struct CppMethod {
    CppMethodName name;
    TypeKindVariable[] params;
    TypeKindVariable return_type;

    invariant() {
        assert(name.length > 0);
        assert(return_type.name.length > 0);
        assert(return_type.type.name.length > 0);
        assert(return_type.type.toString.length > 0);
    }
}

pure @safe nothrow struct CppMethodContainer {
    CppMethod[] methods;
}

pure @safe nothrow struct CppClass {
}
