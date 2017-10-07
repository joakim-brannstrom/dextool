/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.function_;

import llvm_hiwrap.types;

/**
 * Functions in this group operate on LLVMValueRef instances that correspond to
 * llvm::Function instances.
 */
struct FunctionValue {
    import llvm;
    import llvm_hiwrap : Value;
    import llvm_hiwrap.value.basic_block;

    LxFunctionValue value;
    alias value this;

    Value asValue() {
        return Value(value);
    }

    /// Returns: range over the paramters
    auto parameters() {
        return ParametersRange(this);
    }

    /// Obtain the number of basic blocks in a function.
    auto countBasicBlocks() {
        return LLVMCountBasicBlocks(this);
    }

    /// Returns: range over all basic blocks in the function.
    auto basicBlocks() {
        return BasicBlockRange(this);
    }

    /** Obtain the basic block that corresponds to the entry point of a
     * function.
     *
     * @see llvm::Function::getEntryBlock()
     */
    EntryBasicBlock entryBlock() {
        return LLVMGetEntryBasicBlock(value).LxBasicBlock.LxEntryBasicBlock.EntryBasicBlock;
    }

    /** Check whether the given function has a personality function.
     *
     * @see llvm::Function::hasPersonalityFn()
     */
    bool hasPersonalityFn() {
        return LLVMHasPersonalityFn(value) != 0;
    }

    /** Obtain the personality function attached to the function.
     *
     * @see llvm::Function::getPersonalityFn()
     */
    FunctionValue personalityFn() {
        assert(hasPersonalityFn);
        auto v = LLVMGetPersonalityFn(value);
        return v.LxValue.LxUserValue.LxFunctionValue.FunctionValue;
    }

    /**
     * Set the personality function attached to the function.
     *
     * @see llvm::Function::setPersonalityFn()
     */
    //void LLVMSetPersonalityFn(LLVMValueRef Fn, LLVMValueRef PersonalityFn);

    /** Obtain the ID number from a function instance.
     *
     * @see llvm::Function::getIntrinsicID()
     */
    FuncInstrinsicId instrinsicId() {
        return LLVMGetIntrinsicID(value).FuncInstrinsicId;
    }

    /**
     * Obtain the calling function of a function.
     *
     * The returned value corresponds to the LLVMCallConv enumeration.
     *
     * @see llvm::Function::getCallingConv()
     */
    LxCallConv callConv() {
        return LLVMGetFunctionCallConv(value).toCallConv;
    }

    /** Remove a function from its containing module and deletes it.
     *
     * @see llvm::Function::eraseFromParent()
     */
    void remove() {
        LLVMDeleteFunction(this);
    }

    /**
     * Set the calling convention of a function.
     *
     * @see llvm::Function::setCallingConv()
     *
     * @param Fn Function to operate on
     * @param CC LLVMCallConv to set calling convention to
     */
    //void LLVMSetFunctionCallConv(LLVMValueRef Fn, unsigned CC);

    /**
     * Obtain the name of the garbage collector to use during code
     * generation.
     *
     * @see llvm::Function::getGC()
     */
    //const char *LLVMGetGC(LLVMValueRef Fn);

    /**
     * Define the garbage collector to use during code generation.
     *
     * @see llvm::Function::setGC()
     */
    //void LLVMSetGC(LLVMValueRef Fn, const char *Name);

    /**
     * Add an attribute to a function.
     *
     * @see llvm::Function::addAttribute()
     */
    //void LLVMAddAttributeAtIndex(LLVMValueRef F, LLVMAttributeIndex Idx,
    //                             LLVMAttributeRef A);
    //unsigned LLVMGetAttributeCountAtIndex(LLVMValueRef F, LLVMAttributeIndex Idx);
    //void LLVMGetAttributesAtIndex(LLVMValueRef F, LLVMAttributeIndex Idx,
    //                              LLVMAttributeRef *Attrs);
    //LLVMAttributeRef LLVMGetEnumAttributeAtIndex(LLVMValueRef F,
    //                                             LLVMAttributeIndex Idx,
    //                                             unsigned KindID);
    //LLVMAttributeRef LLVMGetStringAttributeAtIndex(LLVMValueRef F,
    //                                               LLVMAttributeIndex Idx,
    //                                               const char *K, unsigned KLen);
    //void LLVMRemoveEnumAttributeAtIndex(LLVMValueRef F, LLVMAttributeIndex Idx,
    //                                    unsigned KindID);
    //void LLVMRemoveStringAttributeAtIndex(LLVMValueRef F, LLVMAttributeIndex Idx,
    //                                      const char *K, unsigned KLen);

    /**
     * Add a target-dependent attribute to a function
     * @see llvm::AttrBuilder::addAttribute()
     */
    //void LLVMAddTargetDependentFunctionAttr(LLVMValueRef Fn, const char *A,
    //                                        const char *V);

    /**
     * Append a basic block to the end of a function.
     *
     * @see llvm::BasicBlock::Create()
     */
    //LLVMBasicBlockRef LLVMAppendBasicBlockInContext(LLVMContextRef C,
    //                                                LLVMValueRef Fn,
    //                                                const char *Name);

    /**
     * Append a basic block to the end of a function using the global
     * context.
     *
     * @see llvm::BasicBlock::Create()
     */
    //LLVMBasicBlockRef LLVMAppendBasicBlock(LLVMValueRef Fn, const char *Name);

    /**
     * Insert a basic block in a function before another basic block.
     *
     * The function to add to is determined by the function of the
     * passed basic block.
     *
     * @see llvm::BasicBlock::Create()
     */
    //LLVMBasicBlockRef LLVMInsertBasicBlockInContext(LLVMContextRef C,
    //                                                LLVMBasicBlockRef BB,
    //                                                const char *Name);

    /**
     * Insert a basic block in a function using the global context.
     *
     * @see llvm::BasicBlock::Create()
     */
    //LLVMBasicBlockRef LLVMInsertBasicBlock(LLVMBasicBlockRef InsertBeforeBB,
    //                                       const char *Name);
}

struct FuncInstrinsicId {
    uint value;
    alias value this;

    /// A normal function has the value 0.
    bool isIntrinsic() {
        return value != 0;
    }
}

// Range over all of the basic blocks in a function.
struct BasicBlockRange {
    import llvm;
    import llvm_hiwrap.value.basic_block;

    const size_t length;

    private LxBasicBlock cur;
    private const LxBasicBlock end;

    this(FunctionValue v) {
        length = LLVMCountBasicBlocks(v);
        cur = LLVMGetFirstBasicBlock(v).LxBasicBlock;
        end = LLVMGetLastBasicBlock(v).LxBasicBlock;
    }

    BasicBlock front() {
        assert(!empty, "Can't get front of an empty range");
        return cur.BasicBlock;
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");
        cur = LLVMGetNextBasicBlock(cur).LxBasicBlock;
    }

    bool empty() {
        return cur == end;
    }
}

struct ParametersRange {
    import llvm;
    import llvm_hiwrap.value.parameter;

    const size_t length;

    private FunctionValue value;

    this(FunctionValue v) {
        value = v;
        length = LLVMCountParams(v);
    }

    ParameterValue opIndex(size_t index) nothrow {
        assert(index < length);
        return LLVMGetParam(value, cast(uint) index).LxValue.ParameterValue;
    }

    import llvm_hiwrap.util;

    mixin IndexedRangeX!ParameterValue;
}

mixin template FunctionAccept(VisitorT, UserT) {
    import llvm_hiwrap.value.function_;

    void implAccept(ref FunctionValue n) {
        import llvm_hiwrap.ast.tree : maybeCallVisit;

        // or it can crash when calling entryBlock
        if (n.countBasicBlocks == 0)
            return;

        auto entry = n.entryBlock;
        // no fallback because IF the user hasn't implemented a visit for
        // EntryBasicBlock it means the user is not interested in visiting that
        // part of the tree.
        maybeCallVisit(this, user, entry);
    }
}

/** A depth-first visitor.
 *
 * See: llvm_hiwrap.ast.tree
 *
 * Accepted node types are:
 *  - FunctionValue
 *
 * and those specified in:
 * See: llvm_hiwrap.value.basic_block
 *
 */
struct FunctionVisitor(UserT) {
    import llvm_hiwrap.value.basic_block : BasicBlockAccept;

    UserT user;

    void visit(ref FunctionValue n) {
        import llvm_hiwrap.ast.tree;

        static void fallback(T)(ref this self, ref UserT user, ref T node) {
            accept(n, self);
        }

        maybeCallVisit(this, user, n);
    }

    mixin FunctionAccept!(FunctionVisitor, UserT);
    mixin BasicBlockAccept!(FunctionVisitor, UserT);
}

@("shall be an instance of FunctionVisitor")
unittest {
    import llvm_hiwrap.ast.tree;

    struct Null {
    }

    FunctionVisitor!Null v;
}
