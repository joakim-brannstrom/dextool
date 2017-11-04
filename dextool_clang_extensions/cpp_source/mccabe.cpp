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
#include "libclang_interop.hpp"

namespace dextool_clang_extension {

namespace McCabe {
struct Result {
    bool hasValue;
    int value;
};

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
