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

    if (decl == nullptr || !llvm::isa<clang::FunctionDecl>(decl))
        return false;
    const clang::FunctionDecl* fnDecl = llvm::cast<const clang::FunctionDecl>(decl);
    if (fnDecl == nullptr)
        return false;

    return fnDecl->isConstexpr();
}

} // namespace dextool_clang_extension
