/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

#include "clang-c/Index.h"

// provides isa<T>
#include "clang/AST/DeclBase.h"
#include "clang/AST/ExprCXX.h"

namespace dextool_clang_extension {

// See: the Expr node
enum class ValueKind {
    unknown,
    lvalue,
    rvalue,
    xvalue,
    glvalue
};

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
};

struct DXOperator {
    bool hasValue;

    OpKind kind;
    CXSourceLocation location;
    int8_t opLength;

    CXCursor cursor;
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

static bool toOpKind(clang::OverloadedOperatorKind opcode, DXOperator& rval) {
    switch (opcode) {
    case clang::OO_New:
        rval.kind = OpKind::OO_New;
        rval.opLength = 3;
        break;
    case clang::OO_Delete:
        rval.kind = OpKind::OO_Delete;
        rval.opLength = 6;
        break;
    case clang::OO_Array_New:
        rval.kind = OpKind::OO_Array_New;
        rval.opLength = 5;
        break;
    case clang::OO_Array_Delete:
        rval.kind = OpKind::OO_Array_Delete;
        rval.opLength = 8;
        break;
    case clang::OO_Plus:
        rval.kind = OpKind::OO_Plus;
        rval.opLength = 1;
        break;
    case clang::OO_Minus:
        rval.kind = OpKind::OO_Minus;
        rval.opLength = 1;
        break;
    case clang::OO_Star:
        rval.kind = OpKind::OO_Star;
        rval.opLength = 1;
        break;
    case clang::OO_Slash:
        rval.kind = OpKind::OO_Slash;
        rval.opLength = 1;
        break;
    case clang::OO_Percent:
        rval.kind = OpKind::OO_Percent;
        rval.opLength = 1;
        break;
    case clang::OO_Caret:
        rval.kind = OpKind::OO_Caret;
        rval.opLength = 1;
        break;
    case clang::OO_Amp:
        rval.kind = OpKind::OO_Amp;
        rval.opLength = 1;
        break;
    case clang::OO_Pipe:
        rval.kind = OpKind::OO_Pipe;
        rval.opLength = 1;
        break;
    case clang::OO_Tilde:
        rval.kind = OpKind::OO_Tilde;
        rval.opLength = 1;
        break;
    case clang::OO_Exclaim:
        rval.kind = OpKind::OO_Exclaim;
        rval.opLength = 1;
        break;
    case clang::OO_Equal:
        rval.kind = OpKind::OO_Equal;
        rval.opLength = 1;
        break;
    case clang::OO_Less:
        rval.kind = OpKind::OO_Less;
        rval.opLength = 1;
        break;
    case clang::OO_Greater:
        rval.kind = OpKind::OO_Greater;
        rval.opLength = 1;
        break;
    case clang::OO_PlusEqual:
        rval.kind = OpKind::OO_PlusEqual;
        rval.opLength = 2;
        break;
    case clang::OO_MinusEqual:
        rval.kind = OpKind::OO_MinusEqual;
        rval.opLength = 2;
        break;
    case clang::OO_StarEqual:
        rval.kind = OpKind::OO_StarEqual;
        rval.opLength = 2;
        break;
    case clang::OO_SlashEqual:
        rval.kind = OpKind::OO_SlashEqual;
        rval.opLength = 2;
        break;
    case clang::OO_PercentEqual:
        rval.kind = OpKind::OO_PercentEqual;
        rval.opLength = 2;
        break;
    case clang::OO_CaretEqual:
        rval.kind = OpKind::OO_CaretEqual;
        rval.opLength = 2;
        break;
    case clang::OO_AmpEqual:
        rval.kind = OpKind::OO_AmpEqual;
        rval.opLength = 2;
        break;
    case clang::OO_PipeEqual:
        rval.kind = OpKind::OO_PipeEqual;
        rval.opLength = 2;
        break;
    case clang::OO_LessLess:
        rval.kind = OpKind::OO_LessLess;
        rval.opLength = 2;
        break;
    case clang::OO_GreaterGreater:
        rval.kind = OpKind::OO_GreaterGreater;
        rval.opLength = 2;
        break;
    case clang::OO_LessLessEqual:
        rval.kind = OpKind::OO_LessLessEqual;
        rval.opLength = 3;
        break;
    case clang::OO_GreaterGreaterEqual:
        rval.kind = OpKind::OO_GreaterGreaterEqual;
        rval.opLength = 3;
        break;
    case clang::OO_EqualEqual:
        rval.kind = OpKind::OO_EqualEqual;
        rval.opLength = 2;
        break;
    case clang::OO_ExclaimEqual:
        rval.kind = OpKind::OO_ExclaimEqual;
        rval.opLength = 2;
        break;
    case clang::OO_LessEqual:
        rval.kind = OpKind::OO_LessEqual;
        rval.opLength = 2;
        break;
    case clang::OO_GreaterEqual:
        rval.kind = OpKind::OO_GreaterEqual;
        rval.opLength = 2;
        break;
    case clang::OO_AmpAmp:
        rval.kind = OpKind::OO_AmpAmp;
        rval.opLength = 2;
        break;
    case clang::OO_PipePipe:
        rval.kind = OpKind::OO_PipePipe;
        rval.opLength = 2;
        break;
    case clang::OO_PlusPlus:
        rval.kind = OpKind::OO_PlusPlus;
        rval.opLength = 2;
        break;
    case clang::OO_MinusMinus:
        rval.kind = OpKind::OO_MinusMinus;
        rval.opLength = 2;
        break;
    case clang::OO_Comma:
        rval.kind = OpKind::OO_Comma;
        rval.opLength = 1;
        break;
    case clang::OO_ArrowStar:
        rval.kind = OpKind::OO_ArrowStar;
        rval.opLength = 3;
        break;
    case clang::OO_Arrow:
        rval.kind = OpKind::OO_Arrow;
        rval.opLength = 2;
        break;
    case clang::OO_Call:
        rval.kind = OpKind::OO_Call;
        rval.opLength = 2;
        break;
    case clang::OO_Subscript:
        rval.kind = OpKind::OO_Subscript;
        rval.opLength = 2;
        break;
    case clang::OO_Conditional:
        rval.kind = OpKind::OO_Conditional;
        rval.opLength = 1;
        break;
    case clang::OO_Coawait:
        rval.kind = OpKind::OO_Coawait;
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
DXOperator dex_getExprOperator(const CXCursor cx_expr) {
    DXOperator rval;
    rval.hasValue = false;
    rval.cursor = cx_expr;

    const clang::Expr* expr = getCursorExpr(cx_expr);
    if (expr == nullptr) {
        return rval;
    }

    const clang::Decl* parent = clang::cxcursor::getCursorParentDecl(cx_expr);
    CXTranslationUnit tu = getCursorTU(cx_expr);

    if (llvm::isa<clang::BinaryOperator>(expr)) {
        const clang::BinaryOperator* op = llvm::cast<const clang::BinaryOperator>(expr);
        if (!toOpKind(op->getOpcode(), rval)) {
            return rval;
        }
        rval.location = translateSourceLocation(*getCursorContext(cx_expr), op->getOperatorLoc());
    } else if (llvm::isa<clang::UnaryOperator>(expr)) {
        const clang::UnaryOperator* op = llvm::cast<const clang::UnaryOperator>(expr);
        if (!toOpKind(op->getOpcode(), rval)) {
            return rval;
        }
        rval.location = translateSourceLocation(*getCursorContext(cx_expr), op->getOperatorLoc());
    } else if (llvm::isa<clang::CXXOperatorCallExpr>(expr)) {
        const clang::CXXOperatorCallExpr* op = llvm::cast<const clang::CXXOperatorCallExpr>(expr);
        if (!toOpKind(op->getOperator(), rval)) {
            return rval;
        }
        rval.location = translateSourceLocation(*getCursorContext(cx_expr), op->getOperatorLoc());
    } else {
        return rval;
    }

    // this shall be the last thing done in this function.
    rval.hasValue = true;
    return rval;
}

struct DXOperatorExprs {
    CXCursor lhs;
    CXCursor rhs;
};

/**
 * TODO is the location what is expected?
 */
DXOperatorExprs dex_getOperatorExprs(const CXCursor cx_expr) {
    DXOperatorExprs rval;
    rval.lhs = clang_getNullCursor();
    rval.rhs = clang_getNullCursor();

    const clang::Expr* expr = getCursorExpr(cx_expr);
    if (expr == nullptr) {
        return rval;
    }

    const clang::Decl* parent = clang::cxcursor::getCursorParentDecl(cx_expr);
    CXTranslationUnit tu = getCursorTU(cx_expr);

    if (llvm::isa<clang::BinaryOperator>(expr)) {
        const clang::BinaryOperator* op = llvm::cast<const clang::BinaryOperator>(expr);
        const clang::Expr* lhs = op->getLHS();
        const clang::Expr* rhs = op->getRHS();

        rval.lhs = clang::cxcursor::dex_MakeCXCursor(lhs, parent, tu, lhs->getSourceRange());
        rval.rhs = clang::cxcursor::dex_MakeCXCursor(rhs, parent, tu, rhs->getSourceRange());
    } else if (llvm::isa<clang::UnaryOperator>(expr)) {
        const clang::UnaryOperator* op = llvm::cast<const clang::UnaryOperator>(expr);
        const clang::Expr* subexpr = op->getSubExpr();

        rval.lhs = clang::cxcursor::dex_MakeCXCursor(subexpr, parent, tu, subexpr->getSourceRange());
    } else if (llvm::isa<clang::CXXOperatorCallExpr>(expr)) {
        const clang::CXXOperatorCallExpr* op = llvm::cast<const clang::CXXOperatorCallExpr>(expr);
        if (op->getNumArgs() == 1) {
            const clang::Expr* lhs = op->getArg(0);
            rval.lhs = clang::cxcursor::dex_MakeCXCursor(lhs, parent, tu, lhs->getSourceRange());
        } else if (op->getNumArgs() == 2) {
            const clang::Expr* lhs = op->getArg(0);
            const clang::Expr* rhs = op->getArg(1);
            rval.lhs = clang::cxcursor::dex_MakeCXCursor(lhs, parent, tu, lhs->getSourceRange());
            rval.rhs = clang::cxcursor::dex_MakeCXCursor(rhs, parent, tu, rhs->getSourceRange());
        }
    } else {
        return rval;
    }

    return rval;
}

ValueKind dex_getExprValueKind(const CXCursor cx_expr) {
    const clang::Expr* expr = getCursorExpr(cx_expr);
    if (expr == nullptr) {
        return ValueKind::unknown;
    }

    if (expr->isLValue()) {
        return ValueKind::lvalue;
    }
    if (expr->isRValue()) {
        return ValueKind::rvalue;
    }
    if (expr->isXValue()) {
        return ValueKind::xvalue;
    }
    if (expr->isGLValue()) {
        return ValueKind::glvalue;
    }

    return ValueKind::unknown;
}

} // NS: dextool_clang_extension
