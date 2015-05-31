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
module generator.stub.types;

import std.typecons : Typedef, Tuple;

import clang.c.index : CX_CXXAccessSpecifier;

import dsrcgen.cpp;

import translator.Type : TypeKind;

package:

/// Prefix used for prepending generated code with a unique string to avoid name collisions.
alias StubPrefix = Typedef!(string, string.init, "StubPrefix");
/// Name of a C++ class/struct/namespace.
alias CppClassStructNsName = Typedef!(string, string.init, "CppClassStructNsName");
/// Nesting of C++ class/struct/namespace.
alias CppNesting = CppClassStructNsName[];
/// Name of a C++ namespace.
alias CppNs = Typedef!(string, string.init, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];

alias HdrFilename = Typedef!(string, string.init, "HeaderFilename");

//TODO use the following typedefs in CppHdrImpl to avoid confusing hdr and impl.
alias CppModuleHdr = Typedef!(CppModule, CppModule.init, "CppHeader");
alias CppModuleImpl = Typedef!(CppModule, CppModule.init, "CppImplementation");
alias CppHdrImpl = Tuple!(CppModule, "hdr", CppModule, "impl");

// To avoid confusing all the different strings with the only differentiating
// fact being the variable name the idea of lots-of-typing from Haskell is
// borrowed. Type systems are awesome.
alias CppAccessSpecifier = Typedef!(CX_CXXAccessSpecifier, CX_CXXAccessSpecifier.init,
    "CppAccess");
///TODO create a type callled StubClassName to differentiate between class-being-stubbed and generated stub.
alias CppClassName = Typedef!(string, string.init, "CppClassName");
alias CppClassNesting = Typedef!(string, string.init, "CppNesting");
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppNsNesting = Typedef!(string, string.init, "CppNsNesting");
alias CppType = Typedef!(string, string.init, "CppType");
alias CppVariable = Typedef!(string, string.init, "CppVariable");

alias TypeName = Tuple!(CppType, "type", CppVariable, "name"); //TODO change TypeName to TypeVariable
alias TypeKindVariable = Tuple!(TypeKind, "type", CppVariable, "name");

alias CallbackNs = Typedef!(string, string.init, "CallbackNs");
alias CallbackPrefix = Typedef!(string, string.init, "CallbackPrefix");

alias StubNs = Typedef!(string, string.init, "StubInternalNs");
alias CallbackStruct = Typedef!(string, string.init, "CallbackStructInNs");
alias CallbackContVariable = Typedef!(TypeName, TypeName.init, "CallbackContVariable");
alias CountStruct = Typedef!(string, string.init, "CountStructInNs");
alias CountContVariable = Typedef!(TypeName, TypeName.init, "CountContVariable");
alias StaticStruct = Typedef!(string, string.init, "StaticStructInNs");
alias StaticContVariable = Typedef!(TypeName, TypeName.init, "StaticContVariable");

alias PoolName = Typedef!(string, string.init, "PoolName");

// convenient function for converting Typedef's to string representation.
string str(T)(T value) @property @safe pure nothrow if (is(T : T!TL, TL : string)) {
    return cast(string) value;
}
