// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.data.type;

import std.typecons : Typedef, Tuple, Flag;
import std.variant : Algebraic;

import cpptooling.analyzer.type : TypeKind, TypeKindAttr, TypeResult;
import cpptooling.data.symbol.types : USRType;

/// Name of a C++ namespace.
alias CppNs = Typedef!(string, null, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];
/// Nesting of C++ namespaces as a string.
alias CppNsNesting = Typedef!(string, null, "CppNsNesting");

alias CppVariable = Typedef!(string, null, "CppVariable");
//TODO change to using TypeAttr or TypeKindAttr
alias TypeKindVariable = Tuple!(TypeKindAttr, "type", CppVariable, "name");

// Types for classes
alias CppClassName = Typedef!(string, null, "CppClassName");

///TODO should be Optional type, either it has a nesting or it is "global".
/// Don't check the length and use that as an insidential "no nesting".
alias CppClassNesting = Typedef!(string, null, "CppNesting");

alias CppClassVirtual = Typedef!(ClassVirtualType, ClassVirtualType.Unknown, "CppClassVirtual");

// Types for methods
alias CppMethodName = Typedef!(string, null, "CppMethodName");
alias CppConstMethod = Typedef!(bool, bool.init, "CppConstMethod");
alias CppVirtualMethod = Typedef!(MemberVirtualType, MemberVirtualType.Unknown, "CppVirtualMethod");
alias CppAccess = Typedef!(AccessType, AccessType.Private, "CppAccess");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");

// Shared types between C and Cpp
alias VariadicType = Flag!"isVariadic";
alias CxParam = Algebraic!(TypeKindVariable, TypeKindAttr, VariadicType);
alias CxReturnType = Typedef!(TypeKindAttr, TypeKindAttr.init, "CxReturnType");
alias Location = Tuple!(string, "file", uint, "line", uint, "column");

enum MemberVirtualType {
    Unknown,
    Normal,
    Virtual,
    Pure
}

///TODO is ClassClassificationType better?
enum ClassVirtualType {
    Unknown,
    Normal,
    Virtual,
    VirtualDtor, // only one method, a d'tor and it is virtual
    Abstract,
    Pure
}

enum AccessType {
    Public,
    Protected,
    Private
}

enum StorageClass {
    None,
    Extern,
    Static
}
