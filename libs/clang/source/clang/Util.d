/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Oct 1, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module clang.Util;

import clang.c.Index;

import std.conv;
import std.stdio;

immutable(char*)* strToCArray(string[] arr) @safe {
    import std.string : toStringz;

    if (!arr)
        return null;

    immutable(char*)[] cArr;
    cArr.reserve(arr.length);

    foreach (str; arr)
        cArr ~= str.toStringz;

    return &cArr[0];
}

/**
 * Trusted: on the assumption that clang_getCString is implemented by the LLVM
 * community. Any bugs in them should by now be found.
 */
string toD(CXString cxString) @trusted {
    auto cstr = clang_getCString(cxString);
    auto str = to!(string)(cstr).idup;
    clang_disposeString(cxString);

    return str;
}

U* toCArray(U, T)(T[] arr) @safe {
    if (!arr)
        return null;

    static if (is(typeof(T.init.cx)))
        return arr.map!(e => e.cx).toArray.ptr;

    else
        return &arr[0];
}

template isCX(T) {
    enum bool isCX = __traits(hasMember, T, "cx");
}

template cxName(T) {
    enum cxName = "CX" ~ T.stringof;
}

mixin template CX(string name = "") {
    static if (name.length == 0) {
        mixin("private alias CType = " ~ cxName!(typeof(this)) ~ ";");
    } else {
        mixin("private alias  CType = CX" ~ name ~ ";");
    }

    CType cx;
    alias cx this;

    /**
     * Trusted: on the assumption that dispose as implemented by the LLVM
     * community is good _enough_. Any bugs should by now have been found.
     */
    void dispose() @trusted {
        static if (name.length == 0)
            enum methodName = "clang_dispose" ~ typeof(this).stringof;
        else
            enum methodName = "clang_dispose" ~ name;
        enum methodCall = methodName ~ "(cx);";

        static if (__traits(hasMember, clang.c.Index, methodName))
            mixin(methodCall);
        else
            pragma(msg, "warning: clang dispose not found: " ~ methodName);
    }

    @property bool isValid() @safe pure nothrow const @nogc {
        return cx !is CType.init;
    }
}
