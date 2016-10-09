/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.nodes;

enum CXCursorKind_PrefixLen = "CXCursor_".length;

// dfmt off
immutable string[] TranslationUnitSeq = [
    "CXCursor_TranslationUnit"
    ];
// dfmt on

// dfmt off
immutable string[] AttributeSeq = [
    "CXCursor_UnexposedAttr",
    "CXCursor_IBActionAttr",
    "CXCursor_IBOutletAttr",
    "CXCursor_IBOutletCollectionAttr",
    "CXCursor_CXXFinalAttr",
    "CXCursor_CXXOverrideAttr",
    "CXCursor_AnnotateAttr",
    "CXCursor_AsmLabelAttr",
    "CXCursor_PackedAttr",
    "CXCursor_PureAttr",
    "CXCursor_ConstAttr",
    "CXCursor_NoDuplicateAttr",
    "CXCursor_CUDAConstantAttr",
    "CXCursor_CUDADeviceAttr",
    "CXCursor_CUDAGlobalAttr",
    "CXCursor_CUDAHostAttr",
    "CXCursor_CUDASharedAttr",
    ];

// dfmt on

// dfmt off
immutable string[] DeclarationSeq = [
    "CXCursor_UnexposedDecl",
    "CXCursor_StructDecl",
    "CXCursor_UnionDecl",
    "CXCursor_ClassDecl",
    "CXCursor_EnumDecl",
    "CXCursor_FieldDecl",
    "CXCursor_EnumConstantDecl",
    "CXCursor_FunctionDecl",
    "CXCursor_VarDecl",
    "CXCursor_ParmDecl",
    "CXCursor_ObjCInterfaceDecl",
    "CXCursor_ObjCCategoryDecl",
    "CXCursor_ObjCProtocolDecl",
    "CXCursor_ObjCPropertyDecl",
    "CXCursor_ObjCIvarDecl",
    "CXCursor_ObjCInstanceMethodDecl",
    "CXCursor_ObjCClassMethodDecl",
    "CXCursor_ObjCImplementationDecl",
    "CXCursor_ObjCCategoryImplDecl",
    "CXCursor_TypedefDecl",
    "CXCursor_CXXMethod",
    "CXCursor_Namespace",
    "CXCursor_LinkageSpec",
    "CXCursor_Constructor",
    "CXCursor_Destructor",
    "CXCursor_ConversionFunction",
    "CXCursor_TemplateTypeParameter",
    "CXCursor_NonTypeTemplateParameter",
    "CXCursor_TemplateTemplateParameter",
    "CXCursor_FunctionTemplate",
    "CXCursor_ClassTemplate",
    "CXCursor_ClassTemplatePartialSpecialization",
    "CXCursor_NamespaceAlias",
    "CXCursor_UsingDirective",
    "CXCursor_TypeAliasDecl",
    "CXCursor_ObjCSynthesizeDecl",
    "CXCursor_ObjCDynamicDecl",
    "CXCursor_CXXAccessSpecifier",
    ];
// dfmt on

// dfmt off
immutable string[] DirectiveSeq = [
    "CXCursor_OMPParallelDirective",
    "CXCursor_OMPSimdDirective",
    "CXCursor_OMPForDirective",
    "CXCursor_OMPSectionsDirective",
    "CXCursor_OMPSectionDirective",
    "CXCursor_OMPSingleDirective",
    "CXCursor_OMPParallelForDirective",
    "CXCursor_OMPParallelSectionsDirective",
    "CXCursor_OMPTaskDirective",
    "CXCursor_OMPMasterDirective",
    "CXCursor_OMPCriticalDirective",
    "CXCursor_OMPTaskyieldDirective",
    "CXCursor_OMPBarrierDirective",
    "CXCursor_OMPTaskwaitDirective",
    "CXCursor_OMPFlushDirective",
    "CXCursor_SEHLeaveStmt",
    "CXCursor_OMPOrderedDirective",
    "CXCursor_OMPAtomicDirective",
    "CXCursor_OMPForSimdDirective",
    "CXCursor_OMPParallelForSimdDirective",
    "CXCursor_OMPTargetDirective",
    "CXCursor_OMPTeamsDirective",
    "CXCursor_OMPTaskgroupDirective",
    "CXCursor_OMPCancellationPointDirective",
    "CXCursor_OMPCancelDirective",
    ];
// dfmt on

// dfmt off
immutable string[] ExpressionSeq = [
    "CXCursor_UnexposedExpr",
    "CXCursor_DeclRefExpr",
    "CXCursor_MemberRefExpr",
    "CXCursor_CallExpr",
    "CXCursor_ObjCMessageExpr",
    "CXCursor_BlockExpr",
    "CXCursor_IntegerLiteral",
    "CXCursor_FloatingLiteral",
    "CXCursor_ImaginaryLiteral",
    "CXCursor_StringLiteral",
    "CXCursor_CharacterLiteral",
    "CXCursor_ParenExpr",
    "CXCursor_UnaryOperator",
    "CXCursor_ArraySubscriptExpr",
    "CXCursor_BinaryOperator",
    "CXCursor_CompoundAssignOperator",
    "CXCursor_ConditionalOperator",
    "CXCursor_CStyleCastExpr",
    "CXCursor_CompoundLiteralExpr",
    "CXCursor_InitListExpr",
    "CXCursor_AddrLabelExpr",
    "CXCursor_StmtExpr",
    "CXCursor_GenericSelectionExpr",
    "CXCursor_GNUNullExpr",
    "CXCursor_CXXStaticCastExpr",
    "CXCursor_CXXDynamicCastExpr",
    "CXCursor_CXXReinterpretCastExpr",
    "CXCursor_CXXConstCastExpr",
    "CXCursor_CXXFunctionalCastExpr",
    "CXCursor_CXXTypeidExpr",
    "CXCursor_CXXBoolLiteralExpr",
    "CXCursor_CXXNullPtrLiteralExpr",
    "CXCursor_CXXThisExpr",
    "CXCursor_CXXThrowExpr",
    "CXCursor_CXXNewExpr",
    "CXCursor_CXXDeleteExpr",
    "CXCursor_UnaryExpr",
    "CXCursor_ObjCStringLiteral",
    "CXCursor_ObjCEncodeExpr",
    "CXCursor_ObjCSelectorExpr",
    "CXCursor_ObjCProtocolExpr",
    "CXCursor_ObjCBridgedCastExpr",
    "CXCursor_PackExpansionExpr",
    "CXCursor_SizeOfPackExpr",
    "CXCursor_LambdaExpr",
    "CXCursor_ObjCBoolLiteralExpr",
    "CXCursor_ObjCSelfExpr",
    ];
// dfmt on

// dfmt off
immutable string[] PreprocessorSeq = [
    "CXCursor_PreprocessingDirective",
    "CXCursor_MacroDefinition",
    "CXCursor_MacroExpansion",
    // Overlaps with MacroExpansion
    //CXCursor_MacroInstantiation,
    "CXCursor_InclusionDirective",
];
// dfmt on

// dfmt off
immutable string[] ReferenceSeq = [
    "CXCursor_ObjCSuperClassRef",
    "CXCursor_ObjCProtocolRef",
    "CXCursor_ObjCClassRef",
    "CXCursor_TypeRef",
    "CXCursor_CXXBaseSpecifier",
    "CXCursor_TemplateRef",
    "CXCursor_NamespaceRef",
    "CXCursor_MemberRef",
    "CXCursor_LabelRef",
    "CXCursor_OverloadedDeclRef",
    "CXCursor_VariableRef",
];
// dfmt on

// dfmt off
immutable string[] StatementSeq = [
    "CXCursor_UnexposedStmt",
    "CXCursor_LabelStmt",
    "CXCursor_CompoundStmt",
    "CXCursor_CaseStmt",
    "CXCursor_DefaultStmt",
    "CXCursor_IfStmt",
    "CXCursor_SwitchStmt",
    "CXCursor_WhileStmt",
    "CXCursor_DoStmt",
    "CXCursor_ForStmt",
    "CXCursor_GotoStmt",
    "CXCursor_IndirectGotoStmt",
    "CXCursor_ContinueStmt",
    "CXCursor_BreakStmt",
    "CXCursor_ReturnStmt",
    // overlaps with AsmStmt
    //CXCursor_GCCAsmStmt,
    "CXCursor_AsmStmt",
    "CXCursor_ObjCAtTryStmt",
    "CXCursor_ObjCAtCatchStmt",
    "CXCursor_ObjCAtFinallyStmt",
    "CXCursor_ObjCAtThrowStmt",
    "CXCursor_ObjCAtSynchronizedStmt",
    "CXCursor_ObjCAutoreleasePoolStmt",
    "CXCursor_ObjCForCollectionStmt",
    "CXCursor_CXXCatchStmt",
    "CXCursor_CXXTryStmt",
    "CXCursor_CXXForRangeStmt",
    "CXCursor_SEHTryStmt",
    "CXCursor_SEHExceptStmt",
    "CXCursor_SEHFinallyStmt",
    "CXCursor_MSAsmStmt",
    "CXCursor_NullStmt",
    "CXCursor_DeclStmt",
    ];
// dfmt on
