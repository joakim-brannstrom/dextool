/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.global;

import llvm_hiwrap.types;

struct ConstantGlobalValue {
    LxConstantGlobalValue value;
    alias value this;

    /**
     * @defgroup LLVMCCoreValueConstantGlobals Global Values
     *
     * This group contains functions that operate on global values. Functions in
     * this group relate to functions in the llvm::GlobalValue class tree.
     *
     * @see llvm::GlobalValue
     *
     * @{
     */

    //LLVMModuleRef LLVMGetGlobalParent(LLVMValueRef Global);
    //LLVMBool LLVMIsDeclaration(LLVMValueRef Global);
    //LLVMLinkage LLVMGetLinkage(LLVMValueRef Global);
    //void LLVMSetLinkage(LLVMValueRef Global, LLVMLinkage Linkage);
    //const char *LLVMGetSection(LLVMValueRef Global);
    //void LLVMSetSection(LLVMValueRef Global, const char *Section);
    //LLVMVisibility LLVMGetVisibility(LLVMValueRef Global);
    //void LLVMSetVisibility(LLVMValueRef Global, LLVMVisibility Viz);
    //LLVMDLLStorageClass LLVMGetDLLStorageClass(LLVMValueRef Global);
    //void LLVMSetDLLStorageClass(LLVMValueRef Global, LLVMDLLStorageClass Class);
    //LLVMBool LLVMHasUnnamedAddr(LLVMValueRef Global);
    //void LLVMSetUnnamedAddr(LLVMValueRef Global, LLVMBool HasUnnamedAddr);

    /**
     * @defgroup LLVMCCoreValueWithAlignment Values with alignment
     *
     * Functions in this group only apply to values with alignment, i.e.
     * global variables, load and store instructions.
     */

    /**
     * Obtain the preferred alignment of the value.
     * @see llvm::AllocaInst::getAlignment()
     * @see llvm::LoadInst::getAlignment()
     * @see llvm::StoreInst::getAlignment()
     * @see llvm::GlobalValue::getAlignment()
     */
    //unsigned LLVMGetAlignment(LLVMValueRef V);

    /**
     * Set the preferred alignment of the value.
     * @see llvm::AllocaInst::setAlignment()
     * @see llvm::LoadInst::setAlignment()
     * @see llvm::StoreInst::setAlignment()
     * @see llvm::GlobalValue::setAlignment()
     */
    //void LLVMSetAlignment(LLVMValueRef V, unsigned Bytes);
}

struct GlobalValue {
    LxGlobalValue value;
    alias value this;

    /**
     * @defgroup LLVMCoreValueConstantGlobalVariable Global Variables
     *
     * This group contains functions that operate on global variable values.
     *
     * @see llvm::GlobalVariable
     *
     * @{
     */
    //LLVMValueRef LLVMAddGlobal(LLVMModuleRef M, LLVMTypeRef Ty, const char *Name);
    //LLVMValueRef LLVMAddGlobalInAddressSpace(LLVMModuleRef M, LLVMTypeRef Ty,
    //                                         const char *Name,
    //                                         unsigned AddressSpace);
    //LLVMValueRef LLVMGetNamedGlobal(LLVMModuleRef M, const char *Name);
    //LLVMValueRef LLVMGetFirstGlobal(LLVMModuleRef M);
    //LLVMValueRef LLVMGetLastGlobal(LLVMModuleRef M);
    //LLVMValueRef LLVMGetNextGlobal(LLVMValueRef GlobalVar);
    //LLVMValueRef LLVMGetPreviousGlobal(LLVMValueRef GlobalVar);
    //void LLVMDeleteGlobal(LLVMValueRef GlobalVar);
    //LLVMValueRef LLVMGetInitializer(LLVMValueRef GlobalVar);
    //void LLVMSetInitializer(LLVMValueRef GlobalVar, LLVMValueRef ConstantVal);
    //LLVMBool LLVMIsThreadLocal(LLVMValueRef GlobalVar);
    //void LLVMSetThreadLocal(LLVMValueRef GlobalVar, LLVMBool IsThreadLocal);
    //LLVMBool LLVMIsGlobalConstant(LLVMValueRef GlobalVar);
    //void LLVMSetGlobalConstant(LLVMValueRef GlobalVar, LLVMBool IsConstant);
    //LLVMThreadLocalMode LLVMGetThreadLocalMode(LLVMValueRef GlobalVar);
    //void LLVMSetThreadLocalMode(LLVMValueRef GlobalVar, LLVMThreadLocalMode Mode);
    //LLVMBool LLVMIsExternallyInitialized(LLVMValueRef GlobalVar);
    //void LLVMSetExternallyInitialized(LLVMValueRef GlobalVar, LLVMBool IsExtInit);
}

struct GlobalAliasValue {
    LxGlobalAliasValue value;
    alias value this;

    /**
     * @defgroup LLVMCoreValueConstantGlobalAlias Global Aliases
     *
     * This group contains function that operate on global alias values.
     *
     * @see llvm::GlobalAlias
     *
     * @{
     */
    //LLVMValueRef LLVMAddAlias(LLVMModuleRef M, LLVMTypeRef Ty, LLVMValueRef Aliasee,
    //                          const char *Name);
}
