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

    /// Represent the operator of an expression that contains an operator (binary or unary).
    extern (C++) struct DXOperator {
        /// Only valid values if true.
        bool hasValue;
        OpKind kind;

        /// The location of the operator
        CXSourceLocation location;
        /// Character length of the operator
        byte opLength;

        /// The cursor for the operator.
        CXCursor cursor;
    }

    enum ValueKind {
        unknown,
        lvalue,
        rvalue,
        xvalue,
        glvalue
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
     *  - unaryOperator
     *  - callExpr
     */
    extern (C++) DXOperator dex_getExprOperator(const CXCursor expr);

    /// The sub-expressions of an operator expression.
    extern (C++) struct DXOperatorExprs {
        CXCursor lhs;
        CXCursor rhs;
    }

    /** Retrieve the left and right side of an operator expression.
     *
     * Acceptable CXCursor kinds are:
     *  - binaryOperator
     *  - unaryOperator
     *  - callExpr
     */
    extern (C++) DXOperatorExprs dex_getOperatorExprs(const CXCursor expr);

    /// Retrieve the value kind of the expression.
    extern (C++) ValueKind dex_getExprValueKind(const CXCursor expr);

    /// Get the first node after the expressions.
    extern (C++) CXCursor dex_getUnderlyingExprNode(const CXCursor expr);

    /// The cursors that make up the inside of the if statement.
    extern (C++) struct DXIfStmt {
        CXCursor init_;
        CXCursor cond;
        CXCursor then;
        CXCursor else_;
    }

    extern (C++) DXIfStmt dex_getIfStmt(const CXCursor cx);
}

Operator getExprOperator(const CXCursor expr) @trusted {
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

/**
 * trusted: the C++ impl check that the node is an expression.
 * It can handle any CursorKind.
 */
ValueKind exprValueKind(const CXCursor expr) @trusted {
    return dex_getExprValueKind(expr);
}

/**
 * trusted: the C++ impl check that the node is an expression.
 * It can handle any CursorKind.
 */
auto getUnderlyingExprNode(const CXCursor expr) @trusted {
    return dex_getUnderlyingExprNode(expr);
}

@safe struct OperatorSubExprs {
    import clang.Cursor;

    Cursor lhs, rhs;
}

@safe struct Operator {
    import std.format : FormatSpec;
    import clang.Cursor;
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

    /// Cursor for the expression that the operator reside in.
    Cursor cursor() const {
        return Cursor(dx.cursor);
    }

    /** Retrieve the sub expressions of an operator expressions.
     *
     * rhs is the null cursor for unary operators.
     *
     * Returns: The sides of the expression.
     *
     * trusted:
     * dex_getOperatorExprs is limited to only being able to handle operator
     * expressions.
     * getExprOperator only processes binary, unary and callExpr cursors.
     * This lead to isValid only returning true when the cursor is of that type.
     * Thus the limitation of dex_getOperatorExprs is fulfilled.
     *
     * TODO Further audit of the C++ implementation of dex_getOperatorExprs is
     * needed.
     */
    OperatorSubExprs sides() const @trusted {
        OperatorSubExprs r;

        if (isValid) {
            auto sub_exprs = dex_getOperatorExprs(dx.cursor);
            r = OperatorSubExprs(Cursor(sub_exprs.lhs), Cursor(sub_exprs.rhs));
        }

        return r;
    }

    SourceLocation location() const {
        return SourceLocation(dx.location);
    }

    /// The character length of the operator.
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

IfStmt getIfStmt(const CXCursor cx) @trusted {
    IfStmt rval;
    if (clang_getCursorKind(cx) == CXCursorKind.ifStmt)
        return IfStmt(cx, dex_getIfStmt(cx));

    return rval;
}

@safe struct IfStmt {
    import std.format : FormatSpec;
    import clang.Cursor;

    private Cursor cx;
    private DXIfStmt stmt;

    this(const CXCursor parent_, DXIfStmt stmt) {
        this.cx = Cursor(parent_);
        this.stmt = stmt;
    }

    Cursor cursor() const {
        return cx;
    }

    Cursor init_() const {
        return Cursor(stmt.init_);
    }

    Cursor cond() const {
        return Cursor(stmt.cond);
    }

    Cursor then() const {
        return Cursor(stmt.then);
    }

    Cursor else_() const {
        return Cursor(stmt.else_);
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
        import std.algorithm : copy, map, joiner, filter;
        import std.range : put;

        put(w, "if (");
        if (init_.isValid) {
            () @trusted{ init_.tokens.map!(a => a.spelling).joiner(" ").copy(w); }();
            put(w, "; ");
        }
        () @trusted{ cond.tokens.map!(a => a.spelling).joiner(" ").copy(w); }();
        put(w, ") ");

        foreach (c; [then, else_].filter!(a => a.isValid)) {
            () @trusted{
                auto toks = c.tokens;
                // only one case here and that is a `return foo;`. The trailing
                // `;` is not part of the token range so an extra has to be
                // appended at the end.
                bool is_keyword = toks.length > 0 && toks[0].kind == CXTokenKind.keyword;
                c.tokens.map!(a => a.spelling).joiner(" ").copy(w);
                if (is_keyword)
                    put(w, "; ");
            }();
        }
    }
}
