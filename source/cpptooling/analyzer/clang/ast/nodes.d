/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.nodes;

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
immutable string[] ExtraSeq = [
    "moduleImportDecl",
    "typeAliasTemplateDecl",
    "staticAssert",
    "friendDecl",
    ];
// dfmt on

// dfmt off
immutable string[] AttributeSeq = [
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
    "dllImport",
    ];

// dfmt on

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
immutable string[] DirectiveSeq = [
    "ompParallelDirective",
    "ompSimdDirective",
    "ompForDirective",
    "ompSectionsDirective",
    "ompSectionDirective",
    "ompSingleDirective",
    "ompParallelForDirective",
    "ompParallelSectionsDirective",
    "ompTaskDirective",
    "ompMasterDirective",
    "ompCriticalDirective",
    "ompTaskyieldDirective",
    "ompBarrierDirective",
    "ompTaskwaitDirective",
    "ompFlushDirective",
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
// dfmt on

// dfmt off
immutable string[] ExpressionSeq = [
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
    "objCAvailabilityCheckExpr",
    ];
// dfmt on

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
immutable string[] StatementSeq = [
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
    ];
// dfmt on
