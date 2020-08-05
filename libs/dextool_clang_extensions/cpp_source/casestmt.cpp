/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

#include "clang-c/Index.h"

// provides isa<T>
#include "clang/AST/DeclBase.h"
#include "clang/AST/ExprCXX.h"

namespace dextool_clang_extension {

struct DXCaseStmt {
    bool hasValue;

    /// Location of the colon after the RHS expression.
    CXSourceLocation colonLoc;
    /// The statement that is contained inside the case statement.
    CXCursor subStmt;

    CXSourceLocation beginLoc;
    CXSourceLocation endLoc;
};

DXCaseStmt dex_getCaseStmt(const CXCursor cx) {
    DXCaseStmt rval;
    rval.colonLoc = clang_getNullLocation();
    rval.beginLoc = clang_getNullLocation();
    rval.endLoc = clang_getNullLocation();
    rval.subStmt = clang_getNullCursor();

    const clang::Stmt* stmt = getCursorStmt(cx);
    if (stmt == nullptr || !llvm::isa<clang::CaseStmt>(stmt)) {
        return rval;
    }

    const clang::Decl* parent = clang::cxcursor::getCursorParentDecl(cx);
    CXTranslationUnit tu = getCursorTU(cx);

    const clang::CaseStmt* case_stmt = llvm::cast<const clang::CaseStmt>(stmt);

    const clang::Stmt* subs = case_stmt->getSubStmt();
    if (subs != nullptr) {
        rval.subStmt = clang::cxcursor::dex_MakeCXCursor(subs, parent, tu, subs->getSourceRange());
    }

// the API has changed from 4->8. getStartLoc where finally removed in
// libclang-8.
#if CINDEX_VERSION < 50
    rval.beginLoc = translateSourceLocation(*getCursorContext(cx), case_stmt->getLocStart());
    rval.endLoc = translateSourceLocation(*getCursorContext(cx), case_stmt->getLocEnd());
#else
    rval.beginLoc = translateSourceLocation(*getCursorContext(cx), case_stmt->getBeginLoc());
    rval.endLoc = translateSourceLocation(*getCursorContext(cx), case_stmt->getEndLoc());
#endif
    rval.colonLoc = translateSourceLocation(*getCursorContext(cx), case_stmt->getColonLoc());
    rval.hasValue = true;

    return rval;
}

} // namespace dextool_clang_extension
