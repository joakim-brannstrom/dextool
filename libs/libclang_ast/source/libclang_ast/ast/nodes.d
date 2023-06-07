/**
Copyright: Copyright (c) 2016-2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module libclang_ast.ast.nodes;

import clang.c.Index : CINDEX_VERSION_MINOR;

enum Lllvm16Plus = 63;

string makeNodeClassName(string s) {
    import std.string;

    return s[0 .. 1].toUpper ~ s[1 .. $];
}

// dfmt off
immutable string[] TranslationUnitSeq = [
    "translationUnit"
    ];
// dfmt on

// dfmt off
immutable string[] ExtraSeq1 = [
    "moduleImportDecl",
    "typeAliasTemplateDecl",
    "staticAssert",
    "friendDecl",];
immutable string[] ExtraSeq2 = [
    "conceptDecl",
    "overloadCandidate",
];
// dfmt on
static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] ExtraSeq = ExtraSeq1 ~ ExtraSeq2;
} else {
    alias ExtraSeq = ExtraSeq1;
}

// dfmt off
immutable string[] AttributeSeq1 = [
    "unexposedAttr",
    "ibActionAttr",
    "ibOutletAttr",
    "ibOutletCollectionAttr",
    "cxxFinalAttr",
    "cxxOverrideAttr",
    "annotateAttr",
    "asmLabelAttr",
    "packedAttr",
    "pureAttr",
    "constAttr",
    "noDuplicateAttr",
    "cudaConstantAttr",
    "cudaDeviceAttr",
    "cudaGlobalAttr",
    "cudaHostAttr",
    "cudaSharedAttr",
    "visibilityAttr",
    "dllExport",
    "dllImport"
];
immutable AttributeSeq2 = [
    "nsReturnsRetained",
    "nsReturnsNotRetained",
    "nsReturnsAutoreleased",
    "nsConsumesSelf",
    "nsConsumed",
    "objCException",
    "objCNSObject",
    "objCIndependentClass",
    "objCPreciseLifetime",
    "objCReturnsInnerPointer",
    "objCRequiresSuper",
    "objCRootClass",
    "objCSubclassingRestricted",
    "objCExplicitProtocolImpl",
    "objCDesignatedInitializer",
    "objCRuntimeVisible",
    "objCBoxable",
    "flagEnum",
    "convergentAttr",
    "warnUnusedAttr",
    "warnUnusedResultAttr",
    "alignedAttr",
];
// dfmt on

static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] AttributeSeq = AttributeSeq1 ~ AttributeSeq2;
} else {
    alias AttributeSeq = AttributeSeq1;
}

// dfmt off
immutable string[] DeclarationSeq = [
    "unexposedDecl",
    "structDecl",
    "unionDecl",
    "classDecl",
    "enumDecl",
    "fieldDecl",
    "enumConstantDecl",
    "functionDecl",
    "varDecl",
    "parmDecl",
    "objCInterfaceDecl",
    "objCCategoryDecl",
    "objCProtocolDecl",
    "objCPropertyDecl",
    "objCIvarDecl",
    "objCInstanceMethodDecl",
    "objCClassMethodDecl",
    "objCImplementationDecl",
    "objCCategoryImplDecl",
    "typedefDecl",
    "cxxMethod",
    "namespace",
    "linkageSpec",
    "constructor",
    "destructor",
    "conversionFunction",
    "templateTypeParameter",
    "nonTypeTemplateParameter",
    "templateTemplateParameter",
    "functionTemplate",
    "classTemplate",
    "classTemplatePartialSpecialization",
    "namespaceAlias",
    "usingDirective",
    "typeAliasDecl",
    "objCSynthesizeDecl",
    "objCDynamicDecl",
    "cxxAccessSpecifier",
    ];
// dfmt on

// dfmt off
immutable string[] ExpressionSeq1 = [
    "unexposedExpr",
    "declRefExpr",
    "memberRefExpr",
    "callExpr",
    "objCMessageExpr",
    "blockExpr",
    "integerLiteral",
    "floatingLiteral",
    "imaginaryLiteral",
    "stringLiteral",
    "characterLiteral",
    "parenExpr",
    "unaryOperator",
    "arraySubscriptExpr",
    "binaryOperator",
    "compoundAssignOperator",
    "conditionalOperator",
    "cStyleCastExpr",
    "compoundLiteralExpr",
    "initListExpr",
    "addrLabelExpr",
    "stmtExpr",
    "genericSelectionExpr",
    "gnuNullExpr",
    "cxxStaticCastExpr",
    "cxxDynamicCastExpr",
    "cxxReinterpretCastExpr",
    "cxxConstCastExpr",
    "cxxFunctionalCastExpr",
    "cxxTypeidExpr",
    "cxxBoolLiteralExpr",
    "cxxNullPtrLiteralExpr",
    "cxxThisExpr",
    "cxxThrowExpr",
    "cxxNewExpr",
    "cxxDeleteExpr",
    "unaryExpr",
    "objCStringLiteral",
    "objCEncodeExpr",
    "objCSelectorExpr",
    "objCProtocolExpr",
    "objCBridgedCastExpr",
    "packExpansionExpr",
    "sizeOfPackExpr",
    "lambdaExpr",
    "objCBoolLiteralExpr",
    "objCSelfExpr",
    "ompArraySectionExpr",
    "objCAvailabilityCheckExpr"
];
immutable string[] ExpressionSeq2 = [
    "fixedPointLiteral",
    "ompArrayShapingExpr",
    "ompIteratorExpr",
    "cxxAddrspaceCastExpr",
    "conceptSpecializationExpr",
    "requiresExpr",
    "cxxParenListInitExpr",
];
// dfmt on

static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] ExpressionSeq = ExpressionSeq1 ~ ExpressionSeq2;
} else {
    immutable string[] ExpressionSeq = ExpressionSeq1;
}

// dfmt off
immutable string[] PreprocessorSeq = [
    "preprocessingDirective",
    "macroDefinition",
    "macroExpansion",
    // Overlaps with MacroExpansion
    //CXCursor_MacroInstantiation,
    "inclusionDirective",
];
// dfmt on

// dfmt off
immutable string[] ReferenceSeq = [
    "objCSuperClassRef",
    "objCProtocolRef",
    "objCClassRef",
    "typeRef",
    "cxxBaseSpecifier",
    "templateRef",
    "namespaceRef",
    "memberRef",
    "labelRef",
    "overloadedDeclRef",
    "variableRef",
];
// dfmt on

// dfmt off
immutable string[] StatementSeq1 = [
    "unexposedStmt",
    "labelStmt",
    "compoundStmt",
    "caseStmt",
    "defaultStmt",
    "ifStmt",
    "switchStmt",
    "whileStmt",
    "doStmt",
    "forStmt",
    "gotoStmt",
    "indirectGotoStmt",
    "continueStmt",
    "breakStmt",
    "returnStmt",
    // overlaps with AsmStmt
    //CXCursor_GCCAsmStmt,
    "asmStmt",
    "objCAtTryStmt",
    "objCAtCatchStmt",
    "objCAtFinallyStmt",
    "objCAtThrowStmt",
    "objCAtSynchronizedStmt",
    "objCAutoreleasePoolStmt",
    "objCForCollectionStmt",
    "cxxCatchStmt",
    "cxxTryStmt",
    "cxxForRangeStmt",
    "sehTryStmt",
    "sehExceptStmt",
    "sehFinallyStmt",
    "msAsmStmt",
    "nullStmt",
    "declStmt",
    "sehLeaveStmt",
    "ompOrderedDirective",
    "ompAtomicDirective",
    "ompForSimdDirective",
    "ompParallelForSimdDirective",
    "ompTargetDirective",
    "ompTeamsDirective",
    "ompTaskgroupDirective",
    "ompCancellationPointDirective",
    "ompCancelDirective",
    "ompTargetDataDirective",
    "ompTaskLoopDirective",
    "ompTaskLoopSimdDirective",
    "ompDistributeDirective",
    "ompTargetEnterDataDirective",
    "ompTargetExitDataDirective",
    "ompTargetParallelDirective",
    "ompTargetParallelForDirective",
    "ompTargetUpdateDirective",
    "ompDistributeParallelForDirective",
    "ompDistributeParallelForSimdDirective",
    "ompDistributeSimdDirective",
    "ompTargetParallelForSimdDirective",
    "ompTargetSimdDirective",
    "ompTeamsDistributeDirective",
    "ompTeamsDistributeSimdDirective",
    "ompTeamsDistributeParallelForSimdDirective",
    "ompTeamsDistributeParallelForDirective",
    "ompTargetTeamsDirective",
    "ompTargetTeamsDistributeDirective",
    "ompTargetTeamsDistributeParallelForDirective",
    "ompTargetTeamsDistributeParallelForSimdDirective",
    "ompTargetTeamsDistributeSimdDirective",
];
immutable string[] StatementSeq2 = [
    "builtinBitCastExpr",
    "ompMasterTaskLoopDirective",
    "ompParallelMasterTaskLoopDirective",
    "ompMasterTaskLoopSimdDirective",
    "ompParallelMasterTaskLoopSimdDirective",
    "ompParallelMasterDirective",
    "ompDepobjDirective",
    "ompScanDirective",
    "ompTileDirective",
    "ompCanonicalLoop",
    "ompInteropDirective",
    "ompDispatchDirective",
    "ompMaskedDirective",
    "ompUnrollDirective",
    "ompMetaDirective",
    "ompGenericLoopDirective",
    "ompTeamsGenericLoopDirective",
    "ompTargetTeamsGenericLoopDirective",
    "ompParallelGenericLoopDirective",
    "ompTargetParallelGenericLoopDirective",
    "ompParallelMaskedDirective",
    "ompMaskedTaskLoopDirective",
    "ompMaskedTaskLoopSimdDirective",
    "ompParallelMaskedTaskLoopDirective",
    "ompParallelMaskedTaskLoopSimdDirective",
    "ompErrorDirective",
    ];
// dfmt on
static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] StatementSeq = StatementSeq1 ~ StatementSeq2;
} else {
    alias StatementSeq = StatementSeq1;
}
