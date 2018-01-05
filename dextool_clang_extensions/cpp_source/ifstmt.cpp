/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

#include "clang-c/Index.h"

// provides isa<T>
#include "clang/AST/DeclBase.h"
#include "clang/AST/ExprCXX.h"

namespace dextool_clang_extension {

struct DXIfStmt {
    /// Kind Stmt
    CXCursor init_;
    /// Kind Expr
    CXCursor cond;
    /// Kind Stmt
    CXCursor then;
    /// Kind Stmt
    CXCursor else_;
};

DXIfStmt dex_getIfStmt(const CXCursor cx) {
    DXIfStmt rval;
    rval.init_ = clang_getNullCursor();
    rval.cond = clang_getNullCursor();
    rval.then = clang_getNullCursor();
    rval.else_ = clang_getNullCursor();

    const clang::Stmt* stmt = getCursorStmt(cx);
    if (stmt == nullptr || !llvm::isa<clang::IfStmt>(stmt)) {
        return rval;
    }

    const clang::Decl* parent = clang::cxcursor::getCursorParentDecl(cx);
    CXTranslationUnit tu = getCursorTU(cx);

    const clang::IfStmt* ifstmt = llvm::cast<const clang::IfStmt>(stmt);

    {
        const clang::Stmt* subs = ifstmt->getInit();
        if (subs != nullptr) {
            rval.init_ = clang::cxcursor::dex_MakeCXCursor(subs, parent, tu, subs->getSourceRange());
        }
    }

    {
        const clang::Expr* subs = ifstmt->getCond();
        if (subs != nullptr) {
            rval.cond = clang::cxcursor::dex_MakeCXCursor(subs, parent, tu, subs->getSourceRange());
        }
    }

    {
        const clang::Stmt* subs = ifstmt->getThen();
        if (subs != nullptr) {
            rval.then = clang::cxcursor::dex_MakeCXCursor(subs, parent, tu, subs->getSourceRange());
        }
    }

    {
        const clang::Stmt* subs = ifstmt->getElse();
        if (subs != nullptr) {
            rval.else_ = clang::cxcursor::dex_MakeCXCursor(subs, parent, tu, subs->getSourceRange());
        }
    }

    return rval;
}

} // NS: dextool_clang_extension
