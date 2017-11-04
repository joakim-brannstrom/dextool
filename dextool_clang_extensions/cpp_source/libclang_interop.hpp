/** Datastructures and basic utility to provide interoperability with libclang.
 *
 * I am unsure if the license should be Boost or the one used by the LLVM team.
 *
 * @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
 * @date 2017
 * @author Joakim Brännström (joakim.brannstrom@gmx.com)
 */
#ifndef LIBCLANG_INTEROP_HPP
#define LIBCLANG_INTEROP_HPP

// Clang includes
#include <clang/Analysis/CFG.h>
#include <clang/Frontend/FrontendAction.h>

// needed for use and implementation of getCursorExpr
#include "clang/AST/Expr.h"

// ### begin ugly hack
// Exposing libclang data structures that are ABI compatible with those in
// libclang.

namespace clang {
class ASTUnit;
class CIndexer;

namespace index {
class CommentToXMLConverter;
} // namespace index
} // namespace clang

// See: CXTranslationUnit.h
// Replaced uninteresting parts with void*
struct CXTranslationUnitImpl {
    clang::CIndexer* CIdx;
    clang::ASTUnit* TheASTUnit;
    void* StringPool;
    void* Diagnostics;
    void* OverridenCursorsPool;
    clang::index::CommentToXMLConverter* CommentToXML;
};

// See: Index.h
typedef struct CXTranslationUnitImpl* CXTranslationUnit;

// ### end ugly hack

namespace dextool_clang_extension {

// See: CXCursor.cpp
CXTranslationUnit getCursorTU(CXCursor Cursor);

// See: CXCursor.cpp
clang::ASTUnit* getCursorASTUnit(CXCursor Cursor);

// See: CXCursor.cpp
clang::ASTContext* getCursorContext(CXCursor Cursor);

// See: CXCursor.cpp
const clang::Decl* getCursorDecl(CXCursor Cursor);

// See: CXCursor.cpp
const clang::Expr* getCursorExpr(CXCursor Cursor);

// See: CXCursor.cpp
const clang::Stmt* getCursorStmt(CXCursor Cursor);

// See: CIndex.cpp
CXSourceLocation getLocation(CXCursor C);

// See: CXSourceLocation.h
/// Translate a Clang source location into a CIndex source location.
CXSourceLocation translateSourceLocation(clang::ASTContext& Context,
                                         clang::SourceLocation Loc);

// See: CXSourceLocation.h
/// Translate a Clang source location into a CIndex source location.
CXSourceLocation translateSourceLocation(const clang::SourceManager& SM, const clang::LangOptions& LangOpts,
                                         clang::SourceLocation Loc);

} // NS: dextool_clang_extension

#endif // LIBCLANG_INTEROP_HPP
