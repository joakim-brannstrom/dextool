/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Algorithm for classifying a class such as being "pure virtual".
*/
module cpptooling.data.class_classification;

import std.typecons : Flag;
import logger = std.experimental.logger;

import cpptooling.data.representation : CppClass, CppMethod, CppMethodOp, CppCtor, CppDtor;
import cpptooling.data.type : MemberVirtualType;

/// The state and result of the classification is in.
enum State {
    Unknown,
    Normal,
    Virtual,
    VirtualDtor, // only one method, a d'tor and it is virtual
    Abstract,
    Pure
}

/// The type the method is.
enum MethodKind {
    Unknown,
    Method,
    Ctor,
    Dtor,
}

/// Input data for determining the next State.
struct InData {
    /// Metadata regarding normal/virtual/pure of the indata.
    MemberVirtualType value;

    /// The kind of method.
    MethodKind t;
}

//TODO change to being a template so to!ClassMethod(..) can be used
//TODO move to representation.d
private auto toInData(T)(T func) @trusted
out (result) {
    assert(result.value != MemberVirtualType.Unknown);
}
body {
    import std.variant : visit;

    //dfmt off
    return func.visit!(
        (const CppMethod a) => InData(a.classification(), MethodKind.Method),
        (const CppMethodOp a) => InData(a.classification(), MethodKind.Method),
        // A ctor can't be anything else than Normal
        (const CppCtor a) => InData(MemberVirtualType.Normal, MethodKind.Ctor),
        (const CppDtor a) => InData(a.classification(), MethodKind.Dtor));
    //dfmt on
}

/** Classify a class from a current state.
 *
 * Problem that this function solve:
 * Clang have no property that classifies a class as virtual/abstract/pure.
 *
 * Design:
 * The classification is sequential according to an informal FSM.
 * The classification only depend on the input data. No globals, no side effects.
 *
 * Params:
 *  current = current state of the classification.
 *  method_kind = kind of method
 *  method_virtual_type = kind of "virtuality" the function is
 *  hasMember = a class with any members can at the most be virtual
 *
 * Returns: new classification state.
 */
State classifyClass(in State current, in MethodKind method_kind,
        in MemberVirtualType method_virtual_type, Flag!"hasMember" hasMember) @safe pure {
    import std.algorithm : among;

    auto data = InData(method_virtual_type, method_kind);
    State next = current;

    final switch (current) {
    case State.Pure:
        // a pure interface can't have members
        if (hasMember) {
            next = State.Abstract;
        }  // a non-virtual destructor lowers purity
        else if (data.t == MethodKind.Dtor && data.value == MemberVirtualType.Normal) {
            next = State.Abstract;
        } else if (data.t == MethodKind.Method && data.value == MemberVirtualType.Virtual) {
            next = State.Abstract;
        }
        break;
    case State.Abstract:
        // one or more methods are pure, stay at this state
        break;
    case State.Virtual:
        if (data.value == MemberVirtualType.Pure) {
            next = State.Abstract;
        }
        break;
    case State.VirtualDtor:
        if (data.value == MemberVirtualType.Pure) {
            next = State.Pure;
        } else {
            next = State.Virtual;
        }
        break;
    case State.Normal:
        if (data.t.among(MethodKind.Method, MethodKind.Dtor)
                && data.value == MemberVirtualType.Pure) {
            next = State.Abstract;
        } else if (data.t.among(MethodKind.Method, MethodKind.Dtor)
                && data.value == MemberVirtualType.Virtual) {
            next = State.Virtual;
        }
        break;
    case State.Unknown:
        // ctor cannot affect purity evaluation
        if (data.t == MethodKind.Dtor
                && data.value.among(MemberVirtualType.Pure, MemberVirtualType.Virtual)) {
            next = State.VirtualDtor;
        } else if (data.t != MethodKind.Ctor) {
            final switch (data.value) {
            case MemberVirtualType.Unknown:
                next = State.Unknown;
                break;
            case MemberVirtualType.Normal:
                next = State.Normal;
                break;
            case MemberVirtualType.Virtual:
                next = State.Virtual;
                break;
            case MemberVirtualType.Pure:
                next = State.Pure;
                break;
            }
        }
        break;
    }

    debug {
        import std.conv : to;

        logger.trace(to!string(current), ":", to!string(data), ":",
                to!string(current), "->", to!string(next));
    }

    return next;
}

/// ditto
State classifyClass(in State current, const CppClass.CppFunc p, Flag!"hasMember" hasMember) @safe {
    auto data = toInData(p);
    return classifyClass(current, data.t, data.value, hasMember);
}
