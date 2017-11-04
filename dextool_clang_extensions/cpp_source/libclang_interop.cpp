/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

// used by translateSourceLocation
#include "clang-c/Index.h"
#include "clang/AST/ASTContext.h"
#include "clang/Basic/LangOptions.h"
#include "clang/Basic/SourceLocation.h"

namespace dextool_clang_extension {

using ::llvm::dyn_cast_or_null;

// reimplementation of helper functions from libclang

// See: CXCursor.cpp
CXTranslationUnit getCursorTU(CXCursor Cursor) {
    return static_cast<CXTranslationUnit>(const_cast<void*>(Cursor.data[2]));
}

// See: CXCursor.cpp
clang::ASTUnit* getCursorASTUnit(CXCursor Cursor) {
    CXTranslationUnit TU = getCursorTU(Cursor);
    if (!TU) {
        return nullptr;
    }
    return TU->TheASTUnit;
}

// See: CXCursor.cpp
clang::ASTContext* getCursorContext(CXCursor Cursor) {
    return &getCursorASTUnit(Cursor)->getASTContext();
}

// See: CXCursor.cpp
const clang::Decl* getCursorDecl(CXCursor Cursor) {
    return static_cast<const clang::Decl*>(Cursor.data[0]);
}

// See: CXCursor.cpp
const clang::Expr* getCursorExpr(CXCursor Cursor) {
    return dyn_cast_or_null<clang::Expr>(getCursorStmt(Cursor));
}

// See: CXCursor.cpp
const clang::Stmt* getCursorStmt(CXCursor Cursor) {
    if (Cursor.kind == CXCursor_ObjCSuperClassRef ||
            Cursor.kind == CXCursor_ObjCProtocolRef ||
            Cursor.kind == CXCursor_ObjCClassRef) {
        return nullptr;
    }

    return static_cast<const clang::Stmt*>(Cursor.data[1]);
}

// See: CXSourceLocation.h
/// \brief Translate a Clang source location into a CIndex source location.
CXSourceLocation translateSourceLocation(const clang::SourceManager& SM, const clang::LangOptions& LangOpts,
                                         clang::SourceLocation Loc) {
    if (Loc.isInvalid()) {
        clang_getNullLocation();
    }

    CXSourceLocation Result = { { &SM, &LangOpts, },
        Loc.getRawEncoding()
    };
    return Result;
}


// See: CXSourceLocation.h
CXSourceLocation translateSourceLocation(clang::ASTContext& Context,
                                         clang::SourceLocation Loc) {
    return translateSourceLocation(Context.getSourceManager(),
                                   Context.getLangOpts(),
                                   Loc);
}

// See: CIndex.cpp
CXSourceLocation getLocation(CXCursor C) {
    if (clang_isExpression(C.kind)) {
        const clang::Expr* expr = getCursorExpr(C);
        clang::SourceLocation loc = expr->getLocStart();
        return translateSourceLocation(*getCursorContext(C), loc);
    }

    return clang_getNullLocation();
}

} // NS: dextool_clang_extension {
