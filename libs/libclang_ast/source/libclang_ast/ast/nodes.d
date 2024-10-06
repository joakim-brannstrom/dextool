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
    "TranslationUnit"
    ];
// dfmt on

// dfmt off
immutable string[] ExtraSeq1 = [
    "ModuleImportDecl",
    "TypeAliasTemplateDecl",
    "StaticAssert",
    "FriendDecl",];
immutable string[] ExtraSeq2 = [
    "ConceptDecl",
    "OverloadCandidate",
];
// dfmt on
static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] ExtraSeq = ExtraSeq1 ~ ExtraSeq2;
} else {
    alias ExtraSeq = ExtraSeq1;
}

// dfmt off
immutable string[] AttributeSeq1 = [
    "UnexposedAttr",
    "CXXFinalAttr",
    "CXXOverrideAttr",
    "AnnotateAttr",
    "AsmLabelAttr",
    "PackedAttr",
    "PureAttr",
    "ConstAttr",
    "NoDuplicateAttr",
    "VisibilityAttr",
];
immutable AttributeSeq2 = [
    "FlagEnum",
    "ConvergentAttr",
    "WarnUnusedAttr",
    "WarnUnusedResultAttr",
    "AlignedAttr",
];
// dfmt on

static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] AttributeSeq = AttributeSeq1 ~ AttributeSeq2;
} else {
    alias AttributeSeq = AttributeSeq1;
}

// dfmt off
immutable string[] DeclarationSeq = [
    "UnexposedDecl",
    "StructDecl",
    "UnionDecl",
    "ClassDecl",
    "EnumDecl",
    "FieldDecl",
    "EnumConstantDecl",
    "FunctionDecl",
    "VarDecl",
    "ParmDecl",
    "TypedefDecl",
    "CXXMethod",
    "Namespace",
    "LinkageSpec",
    "Constructor",
    "Destructor",
    "ConversionFunction",
    "TemplateTypeParameter",
    "NonTypeTemplateParameter",
    "TemplateTemplateParameter",
    "FunctionTemplate",
    "ClassTemplate",
    "ClassTemplatePartialSpecialization",
    "NamespaceAlias",
    "UsingDirective",
    "TypeAliasDecl",
    "CXXAccessSpecifier",
    ];
// dfmt on

// dfmt off
immutable string[] ExpressionSeq1 = [
    "UnexposedExpr",
    "DeclRefExpr",
    "MemberRefExpr",
    "CallExpr",
    "BlockExpr",
    "IntegerLiteral",
    "FloatingLiteral",
    "ImaginaryLiteral",
    "StringLiteral",
    "CharacterLiteral",
    "ParenExpr",
    "UnaryOperator",
    "ArraySubscriptExpr",
    "BinaryOperator",
    "CompoundAssignOperator",
    "ConditionalOperator",
    "CStyleCastExpr",
    "CompoundLiteralExpr",
    "InitListExpr",
    "AddrLabelExpr",
    "StmtExpr",
    "GenericSelectionExpr",
    "GNUNullExpr",
    "CXXStaticCastExpr",
    "CXXDynamicCastExpr",
    "CXXReinterpretCastExpr",
    "CXXConstCastExpr",
    "CXXFunctionalCastExpr",
    "CXXTypeidExpr",
    "CXXBoolLiteralExpr",
    "CXXNullPtrLiteralExpr",
    "CXXThisExpr",
    "CXXThrowExpr",
    "CXXNewExpr",
    "CXXDeleteExpr",
    "UnaryExpr",
    "PackExpansionExpr",
    "SizeOfPackExpr",
    "LambdaExpr",
];
immutable string[] ExpressionSeq2 = [
    "FixedPointLiteral",
    "CXXAddrspaceCastExpr",
    "ConceptSpecializationExpr",
    "RequiresExpr",
    "CXXParenListInitExpr",
];
// dfmt on

static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] ExpressionSeq = ExpressionSeq1 ~ ExpressionSeq2;
} else {
    immutable string[] ExpressionSeq = ExpressionSeq1;
}

// dfmt off
immutable string[] PreprocessorSeq = [
    "PreprocessingDirective",
    "MacroDefinition",
    "MacroExpansion",
    // Overlaps with MacroExpansion
    //CXCursor_MacroInstantiation,
    "InclusionDirective",
];
// dfmt on

// dfmt off
immutable string[] ReferenceSeq = [
    "TypeRef",
    "CXXBaseSpecifier",
    "TemplateRef",
    "NamespaceRef",
    "MemberRef",
    "LabelRef",
    "OverloadedDeclRef",
    "VariableRef",
];
// dfmt on

// dfmt off
immutable string[] StatementSeq1 = [
    "UnexposedStmt",
    "LabelStmt",
    "CompoundStmt",
    "CaseStmt",
    "DefaultStmt",
    "IfStmt",
    "SwitchStmt",
    "WhileStmt",
    "DoStmt",
    "ForStmt",
    "GotoStmt",
    "IndirectGotoStmt",
    "ContinueStmt",
    "BreakStmt",
    "ReturnStmt",
    // overlaps with AsmStmt
    //CXCursor_GCCAsmStmt,
    "AsmStmt",
    "CXXCatchStmt",
    "CXXTryStmt",
    "CXXForRangeStmt",
    "SEHTryStmt",
    "SEHExceptStmt",
    "SEHFinallyStmt",
    "MSAsmStmt",
    "NullStmt",
    "DeclStmt",
    "SEHLeaveStmt",
];
immutable string[] StatementSeq2 = [
    "BuiltinBitCastExpr",
    ];
// dfmt on
static if (CINDEX_VERSION_MINOR >= Lllvm16Plus) {
    immutable string[] StatementSeq = StatementSeq1 ~ StatementSeq2;
} else {
    alias StatementSeq = StatementSeq1;
}
