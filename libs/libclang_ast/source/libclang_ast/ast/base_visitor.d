/**
Copyright: Copyright (c) 2016-2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

DO NOT EDIT. THIS FILE IS GENERATED.
See the generator script source/devtool/generator_clang_ast_nodes.d
*/
module libclang_ast.ast.base_visitor;
abstract class Visitor {
    import libclang_ast.ast;

@safe:

    /// Called when entering a node
    void incr() scope {
    }

    /// Called when leaving a node
    void decr() scope {
    }

    /// Only visist the node if the condition is true
    bool precondition() scope {
        return true;
    }

    void visit(scope const TranslationUnit) {
    }

    void visit(scope const Attribute) {
    }

    void visit(scope const UnexposedAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CXXFinalAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CXXOverrideAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const AnnotateAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const AsmLabelAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const PackedAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const PureAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const ConstAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const NoDuplicateAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const VisibilityAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const FlagEnum value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const ConvergentAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const WarnUnusedAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const WarnUnusedResultAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const AlignedAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const Declaration) {
    }

    void visit(scope const UnexposedDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const StructDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const UnionDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ClassDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const EnumDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const FieldDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const EnumConstantDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const FunctionDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const VarDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ParmDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const TypedefDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const CXXMethod value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const Namespace value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const LinkageSpec value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const Constructor value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const Destructor value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ConversionFunction value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const TemplateTypeParameter value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const NonTypeTemplateParameter value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const TemplateTemplateParameter value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const FunctionTemplate value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ClassTemplate value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ClassTemplatePartialSpecialization value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const NamespaceAlias value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const UsingDirective value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const TypeAliasDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const CXXAccessSpecifier value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const Expression) {
    }

    void visit(scope const UnexposedExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const DeclRefExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const MemberRefExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CallExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const BlockExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const IntegerLiteral value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const FloatingLiteral value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ImaginaryLiteral value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const StringLiteral value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CharacterLiteral value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ParenExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const UnaryOperator value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ArraySubscriptExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const BinaryOperator value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CompoundAssignOperator value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ConditionalOperator value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CStyleCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CompoundLiteralExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const InitListExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const AddrLabelExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const StmtExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const GenericSelectionExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const GNUNullExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXStaticCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXDynamicCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXReinterpretCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXConstCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXFunctionalCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXTypeidExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXBoolLiteralExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXNullPtrLiteralExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXThisExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXThrowExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXNewExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXDeleteExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const UnaryExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const PackExpansionExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const SizeOfPackExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const LambdaExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const FixedPointLiteral value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXAddrspaceCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ConceptSpecializationExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const RequiresExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CXXParenListInitExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const Extra) {
    }

    void visit(scope const ModuleImportDecl value) {
        visit(cast(const(Extra)) value);
    }

    void visit(scope const TypeAliasTemplateDecl value) {
        visit(cast(const(Extra)) value);
    }

    void visit(scope const StaticAssert value) {
        visit(cast(const(Extra)) value);
    }

    void visit(scope const FriendDecl value) {
        visit(cast(const(Extra)) value);
    }

    void visit(scope const ConceptDecl value) {
        visit(cast(const(Extra)) value);
    }

    void visit(scope const OverloadCandidate value) {
        visit(cast(const(Extra)) value);
    }

    void visit(scope const Preprocessor) {
    }

    void visit(scope const PreprocessingDirective value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(scope const MacroDefinition value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(scope const MacroExpansion value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(scope const InclusionDirective value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(scope const Reference) {
    }

    void visit(scope const TypeRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const CXXBaseSpecifier value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const TemplateRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const NamespaceRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const MemberRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const LabelRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const OverloadedDeclRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const VariableRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const Statement) {
    }

    void visit(scope const UnexposedStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const LabelStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CompoundStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CaseStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const DefaultStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const IfStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SwitchStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const WhileStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const DoStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ForStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const GotoStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const IndirectGotoStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ContinueStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const BreakStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ReturnStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const AsmStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CXXCatchStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CXXTryStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CXXForRangeStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SEHTryStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SEHExceptStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SEHFinallyStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const MSAsmStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const NullStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const DeclStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SEHLeaveStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const BuiltinBitCastExpr value) {
        visit(cast(const(Statement)) value);
    }

}
