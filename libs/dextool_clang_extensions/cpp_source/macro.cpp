/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

#include "clang-c/Index.h"

// provides isa<T>
#include "clang/AST/DeclBase.h"
#include "clang/AST/ExprCXX.h"

namespace dextool_clang_extension {

bool dex_isInSystemMacro(const CXSourceLocation location) {
    // from CXSourceLocation.cpp
    // function
    // clang_Location_isInSystemHeader(CXSourceLocation location)

    const clang::SourceLocation Loc = clang::SourceLocation::getFromRawEncoding(location.int_data);
    if (Loc.isInvalid())
        return false;

    const clang::SourceManager& SM =
        *static_cast<const clang::SourceManager*>(location.ptr_data[0]);
    return SM.isInSystemMacro(Loc);
}

bool dex_isMacroArgExpansion(const CXSourceLocation location) {
    // from CXSourceLocation.cpp
    // function
    // clang_Location_isInSystemHeader(CXSourceLocation location)

    const clang::SourceLocation Loc = clang::SourceLocation::getFromRawEncoding(location.int_data);
    if (Loc.isInvalid())
        return false;

    const clang::SourceManager& SM =
        *static_cast<const clang::SourceManager*>(location.ptr_data[0]);
    return SM.isMacroArgExpansion(Loc);
}

bool dex_isMacroBodyExpansion(const CXSourceLocation location) {
    // from CXSourceLocation.cpp
    // function
    // clang_Location_isInSystemHeader(CXSourceLocation location)

    const clang::SourceLocation Loc = clang::SourceLocation::getFromRawEncoding(location.int_data);
    if (Loc.isInvalid())
        return false;

    const clang::SourceManager& SM =
        *static_cast<const clang::SourceManager*>(location.ptr_data[0]);
    return SM.isMacroBodyExpansion(Loc);
}

bool dex_isAnyMacro(const CXSourceLocation location) {
    // from CXSourceLocation.cpp
    // function
    // clang_Location_isInSystemHeader(CXSourceLocation location)

    const clang::SourceLocation Loc = clang::SourceLocation::getFromRawEncoding(location.int_data);
    if (Loc.isInvalid())
        return false;

    const clang::SourceManager& SM =
        *static_cast<const clang::SourceManager*>(location.ptr_data[0]);
    return SM.isInSystemMacro(Loc) || SM.isMacroBodyExpansion(Loc) || SM.isMacroArgExpansion(Loc);
}

} // namespace dextool_clang_extension
