/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module clang.Eval;

import clang.c.Index;

import clang.Cursor;
import clang.Util;

/** The Eval class represent an evaluation of a statement. It may or may not
 * succeed.
 */
@safe struct Eval {
    private alias CType = CXEvalResult;

    CType cx;
    alias cx this;

    /** Trusted: on the assumption that dispose as implemented by the LLVM
     * community is good _enough_. Any bugs should by now have been found.
     */
    void dispose() @trusted {
        clang_EvalResult_dispose(cx);
    }

    bool isValid() @safe pure nothrow const @nogc {
        return cx !is CType.init;
    }

    CXEvalResultKind kind() const @trusted {
        return clang_EvalResult_getKind(cast(void*) cx);
    }

    /** Returns the evaluation result as integer if the
     * kind is Int.
     */
    int asInt() const @trusted
    in(kind == CXEvalResultKind.int_, "must be CXEvalResultKind.int_") {
        return clang_EvalResult_getAsInt(cast(void*) cx);
    }

    /** Returns: the evaluation result as a long long integer if the kind is
     * Int.
     *
     * This prevents overflows that may happen if the result is returned
     * with clang_EvalResult_getAsInt.
     */
    long asLong() const @trusted
    in(kind == CXEvalResultKind.int_, "must be CXEvalResultKind.int_") {
        return clang_EvalResult_getAsLongLong(cast(void*) cx);
    }

    /** Returns: the evaluation result as an unsigned integer if the kind is
     * Int and clang_EvalResult_isUnsignedInt is non-zero.
     */
    ulong asUnsigned() const @trusted
    in(kind == CXEvalResultKind.int_, "must be CXEvalResultKind.int_") {
        return clang_EvalResult_getAsUnsigned(cast(void*) cx);
    }

    /// Returns: the evaluation result as double if the kind is double.
    double asDouble() const @trusted
    in(kind == CXEvalResultKind.float_, "must be CXEvalResultKind.float_") {
        return clang_EvalResult_getAsDouble(cast(void*) cx);
    }

    /** Returns: the evaluation result as a constant string if the kind is
     * other than Int or float.
     *
     * User must not free this pointer, instead call clang_EvalResult_dispose
     * on the CXEvalResult returned by clang_Cursor_Evaluate.
     */
    string asStr() const @trusted
    in(kind != CXEvalResultKind.int_ && kind != CXEvalResultKind.float_,
            "must NOT be CXEvalResultKind.int_ or float_") {
        import std.conv : to;

        auto cstr = clang_EvalResult_getAsStr(cast(void*) cx);
        auto str = to!string(cstr).idup;
        return str;
    }

    /** Returns: true if the evaluation result resulted in an unsigned integer.
     */
    bool isUnsignedInt() const @trusted
    in(kind == CXEvalResultKind.int_, "must be CXEvalResultKind.int_") {
        return clang_EvalResult_isUnsignedInt(cast(void*) cx) != 0;
    }
}
