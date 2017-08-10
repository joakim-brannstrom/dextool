/** McCabe calculation utility.
 *
 * @copyright (c) 2017 Peter Goldsborough. All rights reserved.
 * @authors: Joakim Brännström
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 *
 * The content of this file is strongly inspired by Peter Goldsborough's C++Now
 * talk 2017-05-16. The calculation of the McCabe value basically Peter's code.
 *
 * I am unsure if the license should be Boost or the one used by the LLVM team.
 * Some parts of the code are copied from libclang such as the data structures
 * to be able to interface with libclang.
 */
// Clang includes
#include <clang/Analysis/CFG.h>
#include <clang/Frontend/FrontendAction.h>

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

namespace dextool_clang_extension {
namespace {

// See: CXCursor.cpp
CXTranslationUnit getCursorTU(CXCursor Cursor) {
    return static_cast<CXTranslationUnit>(const_cast<void*>(Cursor.data[2]));
}

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

} // NS:
// ### end ugly hack

namespace McCabe {
struct Result {
    bool hasValue;
    int value;
};

using ::llvm::dyn_cast_or_null;

Result calculate(CXCursor cx_decl) {
    const clang::Decl* decl = getCursorDecl(cx_decl);
    if (decl == nullptr)
        return {false, 0};

    const clang::FunctionDecl* func_decl;
    if (auto d = decl->getAsFunction()) {
        func_decl = d;
    } else {
        return {false, 0};
    }

    clang::ASTContext* ctx;
    if (clang::ASTContext* result = getCursorContext(cx_decl)) {
        ctx = result;
    } else {
        return {false, 0};
    }

    const auto CFG = clang::CFG::buildCFG(func_decl,
                                          func_decl->getBody(),
                                          ctx,
                                          clang::CFG::BuildOptions());

    if (!CFG) {
        return {false, 0};
    }

    // -1 for entry and -1 for exit block.
    const int number_of_nodes = CFG->size() - 2;
    int number_of_edges = -2;
    for (const auto* Block : *CFG) {
        number_of_edges += Block->succ_size();
    }

    // E - V + 2 * P
    // 2 * 1 = 2 * numberOfComponents.
    const int complexity = number_of_edges - number_of_nodes + (2 * 1);

    return {true, complexity};
}

} // NS: McCabe

} // NS: dextool_clang_extension
