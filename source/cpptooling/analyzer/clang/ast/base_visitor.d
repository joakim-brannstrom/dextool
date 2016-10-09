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

    void visit(const(IBActionAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(IBOutletAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(IBOutletCollectionAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CXXFinalAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CXXOverrideAttr) value) {
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

    void visit(const(CUDAConstantAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CUDADeviceAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CUDAGlobalAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CUDAHostAttr) value) {
        visit(cast(const(Attribute)) value);
    }

    void visit(const(CUDASharedAttr) value) {
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

    void visit(const(CXXMethod) value) {
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

    void visit(const(CXXAccessSpecifier) value) {
        visit(cast(const(Declaration)) value);
    }

    void visit(const(Directive)) {
    }

    void visit(const(OMPParallelDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPSectionsDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPSectionDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPSingleDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPParallelForDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPParallelSectionsDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPTaskDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPMasterDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPCriticalDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPTaskyieldDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPBarrierDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPTaskwaitDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPFlushDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(SEHLeaveStmt) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPOrderedDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPAtomicDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPParallelForSimdDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPTargetDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPTeamsDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPTaskgroupDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPCancellationPointDirective) value) {
        visit(cast(const(Directive)) value);
    }

    void visit(const(OMPCancelDirective) value) {
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

    void visit(const(GNUNullExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXStaticCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXDynamicCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXReinterpretCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXConstCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXFunctionalCastExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXTypeidExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXBoolLiteralExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXNullPtrLiteralExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXThisExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXThrowExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXNewExpr) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(CXXDeleteExpr) value) {
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

    void visit(const(CXXBaseSpecifier) value) {
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

    void visit(const(CXXCatchStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(CXXTryStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(CXXForRangeStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SEHTryStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SEHExceptStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(SEHFinallyStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(MSAsmStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(NullStmt) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(DeclStmt) value) {
        visit(cast(const(Statement)) value);
    }

}
