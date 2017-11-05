/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

#include "clang-c/Index.h"

// provides isa<T>
#include "clang/AST/DeclBase.h"

#include <stdint.h>

namespace dextool_clang_extension {

enum class OpKind {
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
};

struct DXOperator {
    bool hasValue;

    OpKind kind;
    CXSourceLocation location;
    int8_t opLength;
};

static bool toOpKind(clang::BinaryOperatorKind opcode, DXOperator& rval) {
    switch (opcode) {
    case clang::BO_PtrMemD:
        rval.kind = OpKind::PtrMemD;
        rval.opLength = 2;
        break;
    case clang::BO_PtrMemI:
        rval.kind = OpKind::PtrMemI;
        rval.opLength = 3;
        break;
    case clang::BO_Mul:
        rval.kind = OpKind::Mul;
        rval.opLength = 1;
        break;
    case clang::BO_Div:
        rval.kind = OpKind::Div;
        rval.opLength = 1;
        break;
    case clang::BO_Rem:
        rval.kind = OpKind::Rem;
        rval.opLength = 1;
        break;
    case clang::BO_Add:
        rval.kind = OpKind::Add;
        rval.opLength = 1;
        break;
    case clang::BO_Sub:
        rval.kind = OpKind::Sub;
        rval.opLength = 1;
        break;
    case clang::BO_Shl:
        rval.kind = OpKind::Shl;
        rval.opLength = 2;
        break;
    case clang::BO_Shr:
        rval.kind = OpKind::Shr;
        rval.opLength = 2;
        break;
    case clang::BO_LT:
        rval.kind = OpKind::LT;
        rval.opLength = 1;
        break;
    case clang::BO_GT:
        rval.kind = OpKind::GT;
        rval.opLength = 1;
        break;
    case clang::BO_LE:
        rval.kind = OpKind::LE;
        rval.opLength = 2;
        break;
    case clang::BO_GE:
        rval.kind = OpKind::GE;
        rval.opLength = 2;
        break;
    case clang::BO_EQ:
        rval.kind = OpKind::EQ;
        rval.opLength = 2;
        break;
    case clang::BO_NE:
        rval.kind = OpKind::NE;
        rval.opLength = 2;
        break;
    case clang::BO_And:
        rval.kind = OpKind::And;
        rval.opLength = 1;
        break;
    case clang::BO_Xor:
        rval.kind = OpKind::Xor;
        rval.opLength = 1;
        break;
    case clang::BO_Or:
        rval.kind = OpKind::Or;
        rval.opLength = 1;
        break;
    case clang::BO_LAnd:
        rval.kind = OpKind::LAnd;
        rval.opLength = 2;
        break;
    case clang::BO_LOr:
        rval.kind = OpKind::LOr;
        rval.opLength = 2;
        break;
    case clang::BO_Assign:
        rval.kind = OpKind::Assign;
        rval.opLength = 1;
        break;
    case clang::BO_MulAssign:
        rval.kind = OpKind::MulAssign;
        rval.opLength = 2;
        break;
    case clang::BO_DivAssign:
        rval.kind = OpKind::DivAssign;
        rval.opLength = 2;
        break;
    case clang::BO_RemAssign:
        rval.kind = OpKind::RemAssign;
        rval.opLength = 2;
        break;
    case clang::BO_AddAssign:
        rval.kind = OpKind::AddAssign;
        rval.opLength = 2;
        break;
    case clang::BO_SubAssign:
        rval.kind = OpKind::SubAssign;
        rval.opLength = 2;
        break;
    case clang::BO_ShlAssign:
        rval.kind = OpKind::ShlAssign;
        rval.opLength = 3;
        break;
    case clang::BO_ShrAssign:
        rval.kind = OpKind::ShrAssign;
        rval.opLength = 3;
        break;
    case clang::BO_AndAssign:
        rval.kind = OpKind::AndAssign;
        rval.opLength = 2;
        break;
    case clang::BO_XorAssign:
        rval.kind = OpKind::XorAssign;
        rval.opLength = 2;
        break;
    case clang::BO_OrAssign:
        rval.kind = OpKind::OrAssign;
        rval.opLength = 2;
        break;
    case clang::BO_Comma:
        rval.kind = OpKind::Comma;
        rval.opLength = 1;
        break;
    default:
        // unknown operator, skipping.
        return false;
    }

    return true;
}

static bool toOpKind(clang::UnaryOperatorKind opcode, DXOperator& rval) {
    switch (opcode) {
    case clang::UO_PostInc:
        rval.kind = OpKind::PostInc;
        rval.opLength = 2;
        break;
    case clang::UO_PostDec:
        rval.kind = OpKind::PostDec;
        rval.opLength = 2;
        break;
    case clang::UO_PreInc:
        rval.kind = OpKind::PreInc;
        rval.opLength = 2;
        break;
    case clang::UO_PreDec:
        rval.kind = OpKind::PreDec;
        rval.opLength = 2;
        break;
    case clang::UO_AddrOf:
        rval.kind = OpKind::AddrOf;
        rval.opLength = 1;
        break;
    case clang::UO_Deref:
        rval.kind = OpKind::Deref;
        rval.opLength = 1;
        break;
    case clang::UO_Plus:
        rval.kind = OpKind::Plus;
        rval.opLength = 1;
        break;
    case clang::UO_Minus:
        rval.kind = OpKind::Minus;
        rval.opLength = 1;
        break;
    case clang::UO_Not:
        rval.kind = OpKind::Not;
        rval.opLength = 1;
        break;
    case clang::UO_LNot:
        rval.kind = OpKind::LNot;
        rval.opLength = 1;
        break;
    case clang::UO_Real:
        rval.kind = OpKind::Real;
        rval.opLength = 6;
        break;
    case clang::UO_Imag:
        rval.kind = OpKind::Imag;
        rval.opLength = 6;
        break;
    case clang::UO_Extension:
        rval.kind = OpKind::Extension;
        rval.opLength = 13;
        break;
    case clang::UO_Coawait:
        rval.kind = OpKind::Coawait;
        rval.opLength = 8;
        break;
    default:
        // unknown operator, skipping.
        return false;
    }

    return true;
}

/** Retrieve the operator of an expression that is of the subtype BinaryOperator.
 */
DXOperator dex_getExprOperator(CXCursor cx_expr) {
    DXOperator rval;

    const clang::Expr* expr = getCursorExpr(cx_expr);
    if (expr == nullptr) {
        return rval;
    }

    // add check for CXXOperatorCallExpr.
    // From the documentation of BinaryOperator:
    // In C++, where operators may be overloaded, a different kind of
    // expression node (CXXOperatorCallExpr) is used to express the invocation
    // of an overloaded operator with operator syntax. Within a C++ template,
    // whether BinaryOperator or CXXOperatorCallExpr is used to store an
    // expression "x + y" depends on the subexpressions for x and y. If neither
    // x or y is type-dependent, and the "+" operator resolves to a built-in
    // operation, BinaryOperator will be used to express the computation (x and
    // y may still be value-dependent). If either x or y is type-dependent, or
    // if the "+" resolves to an overloaded operator, CXXOperatorCallExpr will
    // be used to express the computation.
    if (llvm::isa<clang::BinaryOperator>(expr)) {
        const clang::BinaryOperator* bo = llvm::cast<const clang::BinaryOperator>(expr);
        if (!toOpKind(bo->getOpcode(), rval)) {
            return rval;
        }
        rval.location = translateSourceLocation(*getCursorContext(cx_expr), bo->getOperatorLoc());
    } else if (llvm::isa<clang::UnaryOperator>(expr)) {
        const clang::UnaryOperator* uo = llvm::cast<const clang::UnaryOperator>(expr);
        if (!toOpKind(uo->getOpcode(), rval)) {
            return rval;
        }
        rval.location = translateSourceLocation(*getCursorContext(cx_expr), uo->getOperatorLoc());
        return rval;
    } else {
        return rval;
    }

    // this shall be the last thing done in this function.
    rval.hasValue = true;
    return rval;
}

} // NS: dextool_clang_extension
