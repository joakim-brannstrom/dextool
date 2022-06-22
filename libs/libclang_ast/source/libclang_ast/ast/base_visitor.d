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

    void visit(scope const TranslationUnit) {
    }

    void visit(scope const Attribute) {
    }

    void visit(scope const UnexposedAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const IbActionAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const IbOutletAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const IbOutletCollectionAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CxxFinalAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CxxOverrideAttr value) {
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

    void visit(scope const CudaConstantAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CudaDeviceAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CudaGlobalAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CudaHostAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const CudaSharedAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const VisibilityAttr value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const DllExport value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(scope const DllImport value) {
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

    void visit(scope const ObjCInterfaceDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCCategoryDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCProtocolDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCPropertyDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCIvarDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCInstanceMethodDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCClassMethodDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCImplementationDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCCategoryImplDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const TypedefDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const CxxMethod value) {
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

    void visit(scope const ObjCSynthesizeDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const ObjCDynamicDecl value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const CxxAccessSpecifier value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(scope const Directive) {
    }

    void visit(scope const OmpParallelDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpForDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpSectionsDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpSectionDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpSingleDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpParallelForDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpParallelSectionsDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTaskDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpMasterDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpCriticalDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTaskyieldDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpBarrierDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTaskwaitDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpFlushDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpOrderedDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpAtomicDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpForSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpParallelForSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTeamsDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTaskgroupDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpCancellationPointDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpCancelDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetDataDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTaskLoopDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTaskLoopSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpDistributeDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetEnterDataDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetExitDataDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetParallelDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetParallelForDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetUpdateDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpDistributeParallelForDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpDistributeParallelForSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpDistributeSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetParallelForSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTeamsDistributeDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTeamsDistributeSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTeamsDistributeParallelForSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTeamsDistributeParallelForDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetTeamsDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetTeamsDistributeDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetTeamsDistributeParallelForDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetTeamsDistributeParallelForSimdDirective value) {
        visit(cast(const(Directive)) value);
    }

    void visit(scope const OmpTargetTeamsDistributeSimdDirective value) {
        visit(cast(const(Directive)) value);
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

    void visit(scope const ObjCMessageExpr value) {
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

    void visit(scope const GnuNullExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxStaticCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxDynamicCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxReinterpretCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxConstCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxFunctionalCastExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxTypeidExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxBoolLiteralExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxNullPtrLiteralExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxThisExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxThrowExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxNewExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const CxxDeleteExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const UnaryExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ObjCStringLiteral value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ObjCEncodeExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ObjCSelectorExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ObjCProtocolExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ObjCBridgedCastExpr value) {
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

    void visit(scope const ObjCBoolLiteralExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ObjCSelfExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const OmpArraySectionExpr value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const ObjCAvailabilityCheckExpr value) {
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

    void visit(scope const ObjCSuperClassRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const ObjCProtocolRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const ObjCClassRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const TypeRef value) {
        visit(cast(const(Reference)) value);
    }

    void visit(scope const CxxBaseSpecifier value) {
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

    void visit(scope const ObjCAtTryStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ObjCAtCatchStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ObjCAtFinallyStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ObjCAtThrowStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ObjCAtSynchronizedStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ObjCAutoreleasePoolStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const ObjCForCollectionStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CxxCatchStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CxxTryStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const CxxForRangeStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SehTryStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SehExceptStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SehFinallyStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const MsAsmStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const NullStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const DeclStmt value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const SehLeaveStmt value) {
        visit(cast(const(Statement)) value);
    }

}
