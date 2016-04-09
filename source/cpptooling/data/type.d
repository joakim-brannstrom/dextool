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

import cpptooling.analyzer.type : TypeKind;

/// Name of a C++ namespace.
alias CppNs = Typedef!(string, string.init, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];
/// Nesting of C++ namespaces as a string.
alias CppNsNesting = Typedef!(string, string.init, "CppNsNesting");

alias CppVariable = Typedef!(string, string.init, "CppVariable");
alias TypeKindVariable = Tuple!(TypeKind, "type", CppVariable, "name");

// Types for classes
alias CppClassName = Typedef!(string, string.init, "CppClassName");

///TODO should be Optional type, either it has a nesting or it is "global".
/// Don't check the length and use that as an insidential "no nesting".
alias CppClassNesting = Typedef!(string, string.init, "CppNesting");

alias CppClassVirtual = Typedef!(ClassVirtualType, ClassVirtualType.Unknown, "CppClassVirtual");

// Types for methods
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppConstMethod = Typedef!(bool, bool.init, "CppConstMethod");
alias CppVirtualMethod = Typedef!(MemberVirtualType, MemberVirtualType.Unknown, "CppVirtualMethod");
alias CppAccess = Typedef!(AccessType, AccessType.Private, "CppAccess");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");

// Shared types between C and Cpp
alias VariadicType = Flag!"isVariadic";
alias CxParam = Algebraic!(TypeKindVariable, TypeKind, VariadicType);
alias CxReturnType = Typedef!(TypeKind, TypeKind.init, "CxReturnType");

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
