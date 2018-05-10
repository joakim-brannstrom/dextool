/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

DO NOT EDIT. THIS FILE IS GENERATED.
See the generator script source/devtool/generator_clang_ast_nodes.d
*/
module cpptooling.analyzer.clang.ast.base_visitor;
abstract class Visitor {
    import cpptooling.analyzer.clang.ast;

@safe:

    /// Called when entering a node
    void incr() {
    }

    /// Called when leaving a node
    void decr() {
    }

    void visit(const TranslationUnit) {
    }

    void visit(const(Attribute)) {
    }

    void visit(const(UnexposedAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(IbActionAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(IbOutletAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(IbOutletCollectionAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CxxFinalAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CxxOverrideAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(AnnotateAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(AsmLabelAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(PackedAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(PureAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(ConstAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(NoDuplicateAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CudaConstantAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CudaDeviceAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CudaGlobalAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CudaHostAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CudaSharedAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(VisibilityAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(DllExport) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(DllImport) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(Declaration)) {
    }

    void visit(const(UnexposedDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(StructDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(UnionDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ClassDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(EnumDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(FieldDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(EnumConstantDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(FunctionDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(VarDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ParmDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCInterfaceDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCCategoryDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCProtocolDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCPropertyDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCIvarDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCInstanceMethodDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCClassMethodDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCImplementationDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCCategoryImplDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(TypedefDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(CxxMethod) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(Namespace) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(LinkageSpec) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(Constructor) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(Destructor) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ConversionFunction) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(TemplateTypeParameter) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(NonTypeTemplateParameter) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(TemplateTemplateParameter) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(FunctionTemplate) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ClassTemplate) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ClassTemplatePartialSpecialization) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(NamespaceAlias) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(UsingDirective) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(TypeAliasDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCSynthesizeDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(ObjCDynamicDecl) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(CxxAccessSpecifier) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(Directive)) {
    }

    void visit(const(OmpParallelDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpSectionsDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpSectionDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpSingleDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpParallelForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpParallelSectionsDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTaskDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpMasterDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpCriticalDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTaskyieldDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpBarrierDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTaskwaitDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpFlushDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpOrderedDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpAtomicDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpParallelForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTeamsDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTaskgroupDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpCancellationPointDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpCancelDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetDataDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTaskLoopDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTaskLoopSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpDistributeDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetEnterDataDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetExitDataDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetParallelDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetParallelForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetUpdateDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpDistributeParallelForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpDistributeParallelForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpDistributeSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetParallelForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTeamsDistributeDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTeamsDistributeSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTeamsDistributeParallelForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTeamsDistributeParallelForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetTeamsDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetTeamsDistributeDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetTeamsDistributeParallelForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetTeamsDistributeParallelForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OmpTargetTeamsDistributeSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(Expression)) {
    }

    void visit(const(UnexposedExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(DeclRefExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(MemberRefExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CallExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCMessageExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(BlockExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(IntegerLiteral) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(FloatingLiteral) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ImaginaryLiteral) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(StringLiteral) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CharacterLiteral) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ParenExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(UnaryOperator) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ArraySubscriptExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(BinaryOperator) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CompoundAssignOperator) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ConditionalOperator) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CStyleCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CompoundLiteralExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(InitListExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(AddrLabelExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(StmtExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(GenericSelectionExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(GnuNullExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxStaticCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxDynamicCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxReinterpretCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxConstCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxFunctionalCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxTypeidExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxBoolLiteralExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxNullPtrLiteralExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxThisExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxThrowExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxNewExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CxxDeleteExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(UnaryExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCStringLiteral) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCEncodeExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCSelectorExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCProtocolExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCBridgedCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(PackExpansionExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(SizeOfPackExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(LambdaExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCBoolLiteralExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCSelfExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(OmpArraySectionExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(ObjCAvailabilityCheckExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(Extra)) {
    }

    void visit(const(ModuleImportDecl) value) {
        visit(cast(const(Extra)) value);
    }

    void visit(const(TypeAliasTemplateDecl) value) {
        visit(cast(const(Extra)) value);
    }

    void visit(const(StaticAssert) value) {
        visit(cast(const(Extra)) value);
    }

    void visit(const(FriendDecl) value) {
        visit(cast(const(Extra)) value);
    }

    void visit(const(Preprocessor)) {
    }

    void visit(const(PreprocessingDirective) value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(const(MacroDefinition) value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(const(MacroExpansion) value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(const(InclusionDirective) value) {
        visit(cast(const(Preprocessor)) value);
    }

    void visit(const(Reference)) {
    }

    void visit(const(ObjCSuperClassRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(ObjCProtocolRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(ObjCClassRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(TypeRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(CxxBaseSpecifier) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(TemplateRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(NamespaceRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(MemberRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(LabelRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(OverloadedDeclRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(VariableRef) value) {
        visit(cast(const(Reference)) value);
    }

    void visit(const(Statement)) {
    }

    void visit(const(UnexposedStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(LabelStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(CompoundStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(CaseStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(DefaultStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(IfStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SwitchStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(WhileStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(DoStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ForStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(GotoStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(IndirectGotoStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ContinueStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(BreakStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ReturnStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(AsmStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ObjCAtTryStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ObjCAtCatchStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ObjCAtFinallyStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ObjCAtThrowStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ObjCAtSynchronizedStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ObjCAutoreleasePoolStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(ObjCForCollectionStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(CxxCatchStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(CxxTryStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(CxxForRangeStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SehTryStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SehExceptStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SehFinallyStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(MsAsmStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(NullStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(DeclStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SehLeaveStmt) value) {
        visit(cast(const(Statement)) value);
    }

}
