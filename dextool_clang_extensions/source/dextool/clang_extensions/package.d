/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file uses the same license as the C++ source code.
*/
module dextool.clang_extensions;

import clang.c.Index;

extern (C++, dextool_clang_extension) {
    extern (C++, McCabe) {
        extern (C++) struct Result {
            /// Only valid values if true.
            bool hasValue;
            /// McCabe complexity
            int value;
        }

        /** Calculate the McCabe complexity.
         *
         * Valid cursors are those with a body.
         * decl.isDefinition must be true.
         *
         * Tested CXCursor kinds that are definitions:
         *  - FunctionDecl
         *  - ConversionFunction
         *  - Constructor
         *  - Destructor
         *  - CXXMethod
         */
        extern (C++) Result calculate(CXCursor decl);
    }

    extern (C++) struct DXOperator {
        /// Only valid values if true.
        bool hasValue;
        OpKind kind;

        /// The location of the operator
        CXSourceLocation location;
        /// Character length of the operator
        byte opLength;
    }

    enum OpKind {
        // See: include/clang/AST/OperationKinds.def under section Binary Operations

        // [C++ 5.5] Pointer-to-member operators.
        PtrMemD, // ".*"
        PtrMemI, // "->*"
        // [C99 6.5.5] Multiplicative operators.
        Mul, // "*"
        Div, // "/"
        Rem, // "%"
        // [C99 6.5.6] Additive operators.
        Add, // "+"
        Sub, // "-"
        // [C99 6.5.7] Bitwise shift operators.
        Shl, // "<<"
        Shr, // ">>"
        // [C99 6.5.8] Relational operators.
        LT, // "<"
        GT, // ">"
        LE, // "<="
        GE, // ">="
        // [C99 6.5.9] Equality operators.
        EQ, // "=="
        NE, // "!="
        // [C99 6.5.10] Bitwise AND operator.
        And, // "&"
        // [C99 6.5.11] Bitwise XOR operator.
        Xor, // "^"
        // [C99 6.5.12] Bitwise OR operator.
        Or, // "|"
        // [C99 6.5.13] Logical AND operator.
        LAnd, // "&&"
        // [C99 6.5.14] Logical OR operator.
        LOr, // "||"
        // [C99 6.5.16] Assignment operators.
        Assign, // "="
        MulAssign, // "*="
        DivAssign, // "/="
        RemAssign, // "%="
        AddAssign, // "+="
        SubAssign, // "-="
        ShlAssign, // "<<="
        ShrAssign, // ">>="
        AndAssign, // "&="
        XorAssign, // "^="
        OrAssign, // "|="
        // [C99 6.5.17] Comma operator.
        Comma, // ","

        // See: include/clang/AST/OperationKinds.def under section Unary Operations
        // [C99 6.5.2.4] Postfix increment and decrement
        PostInc, // "++"
        PostDec, // "--"
        // [C99 6.5.3.1] Prefix increment and decrement
        PreInc, // "++"
        PreDec, // "--"
        // [C99 6.5.3.2] Address and indirection
        AddrOf, // "&"
        Deref, // "*"
        // [C99 6.5.3.3] Unary arithmetic
        Plus, // "+"
        Minus, // "-"
        Not, // "~"
        LNot, // "!"
        // "__real expr"/"__imag expr" Extension.
        Real, // "__real"
        Imag, // "__imag"
        // __extension__ marker.
        Extension, // "__extension__"
        // [C++ Coroutines] co_await operator
        Coawait, // "co_await"

        // See: include/clang/Basic/OperationKinds.def
        // CXXOperatorCallExpr->getOperator kinds
        OO_New, // "new"
        OO_Delete, // "delete"
        OO_Array_New, // "new[]
        OO_Array_Delete, // "delete[]
        OO_Plus, // "+"
        OO_Minus, // "-"
        OO_Star, // "*"
        OO_Slash, // "/"
        OO_Percent, // "%"
        OO_Caret, // "^"
        OO_Amp, // "&"
        OO_Pipe, // "|"
        OO_Tilde, // "~"
        OO_Exclaim, // "!"
        OO_Equal, // "="
        OO_Less, // "<"
        OO_Greater, // ">"
        OO_PlusEqual, // "+="
        OO_MinusEqual, // "-="
        OO_StarEqual, // "*="
        OO_SlashEqual, // "/="
        OO_PercentEqual, // "%="
        OO_CaretEqual, // "^="
        OO_AmpEqual, // "&="
        OO_PipeEqual, // "|="
        OO_LessLess, // "<<"
        OO_GreaterGreater, // ">>"
        OO_LessLessEqual, // "<<="
        OO_GreaterGreaterEqual, // ">>="
        OO_EqualEqual, // "=="
        OO_ExclaimEqual, // "!="
        OO_LessEqual, // "<="
        OO_GreaterEqual, // ">="
        OO_AmpAmp, // "&&"
        OO_PipePipe, // "||"
        OO_PlusPlus, // "++"
        OO_MinusMinus, // "--"
        OO_Comma, // ","
        OO_ArrowStar, // "->*"
        OO_Arrow, // "->"
        OO_Call, // "()"
        OO_Subscript, // "[]"
        OO_Conditional, // "?"
        OO_Coawait, // "co_await"
    }

    /** Retrieve the operator of an expression.
     *
     * Acceptable CXCursor kinds are:
     *  - binaryOperator
     */
    extern (C++) DXOperator dex_getExprOperator(CXCursor expr);
}

Operator getExprOperator(CXCursor expr) @trusted {
    import std.algorithm : among;

    Operator rval;

    // This check is technically not needed because the C++ source code try to do a dynamic cast.
    // But by having a check here it is easier to review that THIS function is correctly implemented.
    // This function is safe for all possible inputs.
    // Note: CXXOperatorCallExpr is denoted callExpr in the C API.
    if (clang_getCursorKind(expr).among(CXCursorKind.binaryOperator,
            CXCursorKind.unaryOperator, CXCursorKind.callExpr)) {
        return Operator(dex_getExprOperator(expr));
    }

    return rval;
}

@safe struct Operator {
    import std.format : FormatSpec;
    import clang.SourceLocation;

    private DXOperator dx;

    this(DXOperator v) {
        dx = v;
    }

    bool isValid() const {
        return dx.hasValue;
    }

    auto kind() const {
        return dx.kind;
    }

    SourceLocation location() const {
        return SourceLocation(dx.location);
    }

    size_t length() const {
        return dx.opLength;
    }

    string toString() const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formatValue, formattedWrite;
        import std.range.primitives : put;

        put(w, "Operator(");
        formatValue(w, kind, fmt);
        put(w, " len:");
        formatValue(w, length, fmt);
        put(w, " ");
        put(w, location.toString);
        put(w, ")");
    }
}
