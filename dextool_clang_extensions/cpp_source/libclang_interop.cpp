/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "libclang_interop.hpp"

// used by translateSourceLocation
#include "clang-c/Index.h"
#include "clang/AST/ASTContext.h"
#include "clang/Basic/LangOptions.h"
#include "clang/Basic/SourceLocation.h"

namespace clang {
namespace cxcursor {
// See: CXCursor.cpp
const clang::Decl* getCursorParentDecl(CXCursor Cursor) {
    return static_cast<const clang::Decl*>(Cursor.data[0]);
}

// See: CXCursor.cpp
CXCursor dex_MakeCXCursor(const clang::Stmt* S, const clang::Decl* Parent,
                          CXTranslationUnit TU,
                          clang::SourceRange RegionOfInterest) {
    assert(S && TU && "Invalid arguments!");
    CXCursorKind K = CXCursor_NotImplemented;

    switch (S->getStmtClass()) {
    case Stmt::NoStmtClass:
        break;

    case Stmt::CaseStmtClass:
        K = CXCursor_CaseStmt;
        break;

    case Stmt::DefaultStmtClass:
        K = CXCursor_DefaultStmt;
        break;

    case Stmt::IfStmtClass:
        K = CXCursor_IfStmt;
        break;

    case Stmt::SwitchStmtClass:
        K = CXCursor_SwitchStmt;
        break;

    case Stmt::WhileStmtClass:
        K = CXCursor_WhileStmt;
        break;

    case Stmt::DoStmtClass:
        K = CXCursor_DoStmt;
        break;

    case Stmt::ForStmtClass:
        K = CXCursor_ForStmt;
        break;

    case Stmt::GotoStmtClass:
        K = CXCursor_GotoStmt;
        break;

    case Stmt::IndirectGotoStmtClass:
        K = CXCursor_IndirectGotoStmt;
        break;

    case Stmt::ContinueStmtClass:
        K = CXCursor_ContinueStmt;
        break;

    case Stmt::BreakStmtClass:
        K = CXCursor_BreakStmt;
        break;

    case Stmt::ReturnStmtClass:
        K = CXCursor_ReturnStmt;
        break;

    case Stmt::GCCAsmStmtClass:
        K = CXCursor_GCCAsmStmt;
        break;

    case Stmt::MSAsmStmtClass:
        K = CXCursor_MSAsmStmt;
        break;

    case Stmt::ObjCAtTryStmtClass:
        K = CXCursor_ObjCAtTryStmt;
        break;

    case Stmt::ObjCAtCatchStmtClass:
        K = CXCursor_ObjCAtCatchStmt;
        break;

    case Stmt::ObjCAtFinallyStmtClass:
        K = CXCursor_ObjCAtFinallyStmt;
        break;

    case Stmt::ObjCAtThrowStmtClass:
        K = CXCursor_ObjCAtThrowStmt;
        break;

    case Stmt::ObjCAtSynchronizedStmtClass:
        K = CXCursor_ObjCAtSynchronizedStmt;
        break;

    case Stmt::ObjCAutoreleasePoolStmtClass:
        K = CXCursor_ObjCAutoreleasePoolStmt;
        break;

    case Stmt::ObjCForCollectionStmtClass:
        K = CXCursor_ObjCForCollectionStmt;
        break;

    case Stmt::CXXCatchStmtClass:
        K = CXCursor_CXXCatchStmt;
        break;

    case Stmt::CXXTryStmtClass:
        K = CXCursor_CXXTryStmt;
        break;

    case Stmt::CXXForRangeStmtClass:
        K = CXCursor_CXXForRangeStmt;
        break;

    case Stmt::SEHTryStmtClass:
        K = CXCursor_SEHTryStmt;
        break;

    case Stmt::SEHExceptStmtClass:
        K = CXCursor_SEHExceptStmt;
        break;

    case Stmt::SEHFinallyStmtClass:
        K = CXCursor_SEHFinallyStmt;
        break;

    case Stmt::SEHLeaveStmtClass:
        K = CXCursor_SEHLeaveStmt;
        break;


    case Stmt::OpaqueValueExprClass:
        if (Expr* Src = cast<OpaqueValueExpr>(S)->getSourceExpr()) {
            return dex_MakeCXCursor(Src, Parent, TU, RegionOfInterest);
        }
        K = CXCursor_UnexposedExpr;
        break;

    case Stmt::PseudoObjectExprClass:
        return dex_MakeCXCursor(cast<PseudoObjectExpr>(S)->getSyntacticForm(),
                                Parent, TU, RegionOfInterest);

    case Stmt::CompoundStmtClass:
        K = CXCursor_CompoundStmt;
        break;

    case Stmt::NullStmtClass:
        K = CXCursor_NullStmt;
        break;

    case Stmt::LabelStmtClass:
        K = CXCursor_LabelStmt;
        break;

    case Stmt::AttributedStmtClass:
        K = CXCursor_UnexposedStmt;
        break;

    case Stmt::DeclStmtClass:
        K = CXCursor_DeclStmt;
        break;

    case Stmt::CapturedStmtClass:
        K = CXCursor_UnexposedStmt;
        break;

    case Stmt::IntegerLiteralClass:
        K = CXCursor_IntegerLiteral;
        break;

    case Stmt::FloatingLiteralClass:
        K = CXCursor_FloatingLiteral;
        break;

    case Stmt::ImaginaryLiteralClass:
        K = CXCursor_ImaginaryLiteral;
        break;

    case Stmt::StringLiteralClass:
        K = CXCursor_StringLiteral;
        break;

    case Stmt::CharacterLiteralClass:
        K = CXCursor_CharacterLiteral;
        break;

    case Stmt::ParenExprClass:
        K = CXCursor_ParenExpr;
        break;

    case Stmt::UnaryOperatorClass:
        K = CXCursor_UnaryOperator;
        break;

    case Stmt::UnaryExprOrTypeTraitExprClass:
    case Stmt::CXXNoexceptExprClass:
        K = CXCursor_UnaryExpr;
        break;

    case Stmt::MSPropertySubscriptExprClass:
    case Stmt::ArraySubscriptExprClass:
        K = CXCursor_ArraySubscriptExpr;
        break;

    case Stmt::OMPArraySectionExprClass:
        K = CXCursor_OMPArraySectionExpr;
        break;

    case Stmt::BinaryOperatorClass:
        K = CXCursor_BinaryOperator;
        break;

    case Stmt::CompoundAssignOperatorClass:
        K = CXCursor_CompoundAssignOperator;
        break;

    case Stmt::ConditionalOperatorClass:
        K = CXCursor_ConditionalOperator;
        break;

    case Stmt::CStyleCastExprClass:
        K = CXCursor_CStyleCastExpr;
        break;

    case Stmt::CompoundLiteralExprClass:
        K = CXCursor_CompoundLiteralExpr;
        break;

    case Stmt::InitListExprClass:
        K = CXCursor_InitListExpr;
        break;

    case Stmt::AddrLabelExprClass:
        K = CXCursor_AddrLabelExpr;
        break;

    case Stmt::StmtExprClass:
        K = CXCursor_StmtExpr;
        break;

    case Stmt::GenericSelectionExprClass:
        K = CXCursor_GenericSelectionExpr;
        break;

    case Stmt::GNUNullExprClass:
        K = CXCursor_GNUNullExpr;
        break;

    case Stmt::CXXStaticCastExprClass:
        K = CXCursor_CXXStaticCastExpr;
        break;

    case Stmt::CXXDynamicCastExprClass:
        K = CXCursor_CXXDynamicCastExpr;
        break;

    case Stmt::CXXReinterpretCastExprClass:
        K = CXCursor_CXXReinterpretCastExpr;
        break;

    case Stmt::CXXConstCastExprClass:
        K = CXCursor_CXXConstCastExpr;
        break;

    case Stmt::CXXFunctionalCastExprClass:
        K = CXCursor_CXXFunctionalCastExpr;
        break;

    case Stmt::CXXTypeidExprClass:
        K = CXCursor_CXXTypeidExpr;
        break;

    case Stmt::CXXBoolLiteralExprClass:
        K = CXCursor_CXXBoolLiteralExpr;
        break;

    case Stmt::CXXNullPtrLiteralExprClass:
        K = CXCursor_CXXNullPtrLiteralExpr;
        break;

    case Stmt::CXXThisExprClass:
        K = CXCursor_CXXThisExpr;
        break;

    case Stmt::CXXThrowExprClass:
        K = CXCursor_CXXThrowExpr;
        break;

    case Stmt::CXXNewExprClass:
        K = CXCursor_CXXNewExpr;
        break;

    case Stmt::CXXDeleteExprClass:
        K = CXCursor_CXXDeleteExpr;
        break;

    case Stmt::ObjCStringLiteralClass:
        K = CXCursor_ObjCStringLiteral;
        break;

    case Stmt::ObjCEncodeExprClass:
        K = CXCursor_ObjCEncodeExpr;
        break;

    case Stmt::ObjCSelectorExprClass:
        K = CXCursor_ObjCSelectorExpr;
        break;

    case Stmt::ObjCProtocolExprClass:
        K = CXCursor_ObjCProtocolExpr;
        break;

    case Stmt::ObjCBoolLiteralExprClass:
        K = CXCursor_ObjCBoolLiteralExpr;
        break;

    case Stmt::ObjCAvailabilityCheckExprClass:
        K = CXCursor_ObjCAvailabilityCheckExpr;
        break;

    case Stmt::ObjCBridgedCastExprClass:
        K = CXCursor_ObjCBridgedCastExpr;
        break;

    case Stmt::BlockExprClass:
        K = CXCursor_BlockExpr;
        break;

    case Stmt::PackExpansionExprClass:
        K = CXCursor_PackExpansionExpr;
        break;

    case Stmt::SizeOfPackExprClass:
        K = CXCursor_SizeOfPackExpr;
        break;

    case Stmt::DeclRefExprClass:
        K = CXCursor_DeclRefExpr;
        break;

    case Stmt::DependentScopeDeclRefExprClass:
    case Stmt::SubstNonTypeTemplateParmExprClass:
    case Stmt::SubstNonTypeTemplateParmPackExprClass:
    case Stmt::FunctionParmPackExprClass:
    case Stmt::UnresolvedLookupExprClass:
    case Stmt::TypoExprClass: // A typo could actually be a DeclRef or a MemberRef
        K = CXCursor_DeclRefExpr;
        break;

    case Stmt::CXXDependentScopeMemberExprClass:
    case Stmt::CXXPseudoDestructorExprClass:
    case Stmt::MemberExprClass:
    case Stmt::MSPropertyRefExprClass:
    case Stmt::ObjCIsaExprClass:
    case Stmt::ObjCIvarRefExprClass:
    case Stmt::ObjCPropertyRefExprClass:
    case Stmt::UnresolvedMemberExprClass:
        K = CXCursor_MemberRefExpr;
        break;

    case Stmt::CallExprClass:
    case Stmt::CXXOperatorCallExprClass:
    case Stmt::CXXMemberCallExprClass:
    case Stmt::CUDAKernelCallExprClass:
    case Stmt::CXXConstructExprClass:
    case Stmt::CXXInheritedCtorInitExprClass:
    case Stmt::CXXTemporaryObjectExprClass:
    case Stmt::CXXUnresolvedConstructExprClass:
    case Stmt::UserDefinedLiteralClass:
        K = CXCursor_CallExpr;
        break;

    case Stmt::LambdaExprClass:
        K = CXCursor_LambdaExpr;
        break;

    default:
        K = CXCursor_UnexposedExpr;
    }


    CXCursor C = { K, 0, { Parent, S, TU } };
    return C;
}


} // NS: cxcursor
} // NS: clang

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
