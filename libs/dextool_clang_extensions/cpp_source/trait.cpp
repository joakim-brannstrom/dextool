/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

#include "clang-c/Index.h"

// provides isa<T>
#include "clang/AST/DeclBase.h"
#include "clang/AST/ExprCXX.h"

namespace dextool_clang_extension {

bool dex_isPotentialConstExpr(const CXCursor cx) {
    const clang::Decl* decl = getCursorDecl(cx);
    if (decl != nullptr) {
        if (llvm::isa<clang::FunctionDecl>(decl)) {
            const clang::FunctionDecl* fnDecl = llvm::cast<const clang::FunctionDecl>(decl);
            if (fnDecl == nullptr)
                return false;
            return fnDecl->isConstexpr();
        }
    }

    const clang::Stmt* stmt = getCursorStmt(cx);
    if (stmt != nullptr) {
        if (llvm::isa<clang::IfStmt>(stmt)) {
            const clang::IfStmt* ifStmt = llvm::cast<const clang::IfStmt>(stmt);
            if (ifStmt == nullptr)
                return false;
            return ifStmt->isConstexpr();
        }
    }

    return false;
}

bool dex_isFunctionTemplateConstExpr(const CXCursor cx) {
    // only tested with clang-12. May work with versions below it.
#if CINDEX_VERSION < 61
    // be conservative
    return true;
#else
    const clang::Decl* decl = getCursorDecl(cx);

    if (decl == nullptr || !llvm::isa<clang::FunctionTemplateDecl>(decl))
        return false;
    const clang::FunctionTemplateDecl* fnDecl = llvm::cast<const clang::FunctionTemplateDecl>(decl);
    if (fnDecl == nullptr || fnDecl->getTemplatedDecl() == nullptr)
        return false;
    const auto tmpl = fnDecl->getTemplatedDecl();
    if (tmpl == nullptr)
        return false;

    return tmpl->isConstexpr();
#endif
}

} // namespace dextool_clang_extension
