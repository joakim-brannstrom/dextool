/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.instruction;

import llvm_hiwrap.types;

import llvm_hiwrap.value.basic_block;
import llvm_hiwrap.value.value;
import llvm_hiwrap.value.user;

/** Functions in this group relate to the inspection and manipulation of
 * individual instructions.
 *
 * In the C++ API, an instruction is modeled by llvm::Instruction. This
 * class has a large number of descendents. llvm::Instruction is a
 * llvm::Value and in the C API, instructions are modeled by
 * LLVMValueRef.
 *
 * This group also contains sub-groups which operate on specific
 * llvm::Instruction types, e.g. llvm::CallInst.
 */
struct InstructionValue {
    import std.typecons : Nullable;
    import llvm;
    import llvm_hiwrap.value.metadata;

    LxInstructionValue value;
    alias value this;

    auto asValue() {
        return Value(value);
    }

    UserValue asUser() {
        return UserValue(value.LxUserValue);
    }

    /// Determine whether an instruction has any metadata attached.
    bool hasMetadata() {
        return LLVMHasMetadata(this) != 0;
    }

    /** Return metadata associated with an instruction value.
     *
     * TODO what is this KindID? very unsafe as is. Seems to be an attribute or
     * it is what LLVMSetMetadata do?
     * TODO what happens if KindID is "unknown"/out of range?
     */
    MetadataNodeValue metadata(uint kind) {
        return LLVMGetMetadata(this, kind).LxValue.LxMetadataNodeValue.MetadataNodeValue;
    }

    /** Set metadata associated with an instruction value.
     */
    void setMetadata(uint kind, Value v) {
        LLVMSetMetadata(this, kind, v);
    }

    /** Obtain the basic block to which an instruction belongs.
     *
     * @see llvm::Instruction::getParent()
     */
    BasicBlock parent() {
        return LLVMGetInstructionParent(value).LxBasicBlock.BasicBlock;
    }

    /** Obtain the instruction that occurs after the one specified.
     *
     * The next instruction will be from the same basic block.
     *
     * If this is the last instruction in a basic block, NULL will be
     * returned.
     */
    Nullable!InstructionValue nextInstr() {
        typeof(return) rval;
        if (auto v = LLVMGetNextInstruction(value))
            rval = v.LxValue.LxInstructionValue.InstructionValue;

        return rval;
    }

    /** Obtain the instruction that occurred before this one.
     *
     * If the instruction is the first instruction in a basic block, NULL
     * will be returned.
     */
    Nullable!InstructionValue prevInstr() {
        typeof(return) rval;
        if (auto v = LLVMGetPreviousInstruction(value))
            rval = v.LxValue.LxInstructionValue.InstructionValue;

        return rval;
    }

    /** Remove and delete an instruction.
     *
     * The instruction specified is removed from its containing building
     * block but is kept alive.
     *
     * @see llvm::Instruction::removeFromParent()
     */
    void removeFromParent() {
        LLVMInstructionRemoveFromParent(value);
    }

    /** Remove and delete an instruction.
     *
     * The instruction specified is removed from its containing building
     * block and then deleted.
     *
     * @see llvm::Instruction::eraseFromParent()
     */
    void eraseFromParent() {
        LLVMInstructionEraseFromParent(value);
    }

    /** Obtain the code opcode for an individual instruction.
     *
     * @see llvm::Instruction::getOpCode()
     */
    LxOpcode opcode() {
        return cast(LxOpcode) LLVMGetInstructionOpcode(this);
    }

    /** Obtain the predicate of an instruction.
     *
     * This is only valid for instructions that correspond to llvm::ICmpInst
     * or llvm::ConstantExpr whose opcode is llvm::Instruction::ICmp.
     *
     * @see llvm::ICmpInst::getPredicate()
     */
    LxIntPredicate intPredicate() {
        assert(opcode == LxOpcode.ICmp);
        return cast(LxIntPredicate) LLVMGetICmpPredicate(this);
    }

    /** Obtain the float predicate of an instruction.
     *
     * This is only valid for instructions that correspond to llvm::FCmpInst
     * or llvm::ConstantExpr whose opcode is llvm::Instruction::FCmp.
     *
     * @see llvm::FCmpInst::getPredicate()
     */
    LxRealPredicate realPredicate() {
        assert(opcode == LxOpcode.FCmp);
        return cast(LxRealPredicate) LLVMGetFCmpPredicate(this);
    }

    /** Create a copy of 'this' instruction that is identical in all ways
     * except the following:
     *   * The instruction has no parent
     *   * The instruction has no name
     *
     * @see llvm::Instruction::clone()
     */
    InstructionValue clone() {
        return LLVMInstructionClone(value).LxValue.LxInstructionValue.InstructionValue;
    }
}

/** Functions in this group apply to instructions that refer to call sites and
 * invocations.
 *
 * These correspond to C++ types in the llvm::CallInst or InvokeInst class
 * tree.
 */
struct InstructionCallValue {
    import llvm;
    import llvm_hiwrap.value.function_;

    LxInstructionCallValue value;
    alias value this;

    auto asValue() {
        return Value(value);
    }

    auto asInstr() {
        return InstructionValue(value);
    }

    /** Obtain the argument count for a call instruction.
     *
     * This expects an LLVMValueRef that corresponds to a llvm::CallInst or
     * llvm::InvokeInst.
     *
     * @see llvm::CallInst::getNumArgOperands()
     * @see llvm::InvokeInst::getNumArgOperands()
     */
    auto numArgOperands() {
        return LLVMGetNumArgOperands(value);
    }

    /**
     * Set the calling convention for a call instruction.
     *
     * This expects an LLVMValueRef that corresponds to a llvm::CallInst or
     * llvm::InvokeInst.
     *
     * @see llvm::CallInst::setCallingConv()
     * @see llvm::InvokeInst::setCallingConv()
     */
    //void LLVMSetInstructionCallConv(LLVMValueRef Instr, unsigned CC);

    /**
     * Obtain the calling convention for a call instruction.
     *
     * This is the opposite of LLVMSetInstructionCallConv(). Reads its
     * usage.
     *
     * @see LLVMSetInstructionCallConv()
     */
    //unsigned LLVMGetInstructionCallConv(LLVMValueRef Instr);

    //void LLVMSetInstrParamAlignment(LLVMValueRef Instr, unsigned index,
    //                                unsigned Align);
    //
    //void LLVMAddCallSiteAttribute(LLVMValueRef C, LLVMAttributeIndex Idx,
    //                              LLVMAttributeRef A);
    //unsigned LLVMGetCallSiteAttributeCount(LLVMValueRef C, LLVMAttributeIndex Idx);
    //void LLVMGetCallSiteAttributes(LLVMValueRef C, LLVMAttributeIndex Idx,
    //                               LLVMAttributeRef *Attrs);
    //LLVMAttributeRef LLVMGetCallSiteEnumAttribute(LLVMValueRef C,
    //                                              LLVMAttributeIndex Idx,
    //                                              unsigned KindID);
    //LLVMAttributeRef LLVMGetCallSiteStringAttribute(LLVMValueRef C,
    //                                                LLVMAttributeIndex Idx,
    //                                                const char *K, unsigned KLen);
    //void LLVMRemoveCallSiteEnumAttribute(LLVMValueRef C, LLVMAttributeIndex Idx,
    //                                     unsigned KindID);
    //void LLVMRemoveCallSiteStringAttribute(LLVMValueRef C, LLVMAttributeIndex Idx,
    //                                       const char *K, unsigned KLen);

    /** Obtain the pointer to the function invoked by this instruction.
     *
     * This expects an LLVMValueRef that corresponds to a llvm::CallInst or
     * llvm::InvokeInst.
     *
     * @see llvm::CallInst::getCalledValue()
     * @see llvm::InvokeInst::getCalledValue()
     *
     * TODO maybe the return type should be a pointer instead?
     */
    FunctionValue calledValue() {
        auto v = LLVMGetCalledValue(value);
        return v.LxValue.LxUserValue.LxFunctionValue.FunctionValue;
    }

    /** Obtain whether a call instruction is a tail call.
     *
     * This only works on llvm::CallInst instructions.
     *
     * @see llvm::CallInst::isTailCall()
     */
    bool isTailCall() {
        return LLVMIsTailCall(value) != 0;
    }

    /** Set whether a call instruction is a tail call.
     *
     * This only works on llvm::CallInst instructions.
     *
     * @see llvm::CallInst::setTailCall()
     */
    void setTailCall(bool onoff) {
        LLVMSetTailCall(value, onoff ? 1 : 0);
    }

    /** Return the normal destination basic block.
     *
     * This only works on llvm::InvokeInst instructions.
     *
     * @see llvm::InvokeInst::getNormalDest()
     */
    BasicBlock normalDest() {
        return LLVMGetNormalDest(value).LxBasicBlock.BasicBlock;
    }

    /** Return the unwind destination basic block.
     *
     * This only works on llvm::InvokeInst instructions.
     *
     * @see llvm::InvokeInst::getUnwindDest()
     */
    BasicBlock unwindDest() {
        return LLVMGetUnwindDest(value).LxBasicBlock.BasicBlock;
    }

    /** Set the normal destination basic block.
     *
     * This only works on llvm::InvokeInst instructions.
     *
     * @see llvm::InvokeInst::setNormalDest()
     */
    void setNormalDest(BasicBlock bb) {
        LLVMSetNormalDest(value, bb);
    }

    /** Set the unwind destination basic block.
     *
     * This only works on llvm::InvokeInst instructions.
     *
     * @see llvm::InvokeInst::setUnwindDest()
     */
    void setUnwindDest(BasicBlock bb) {
        LLVMSetUnwindDest(value, bb);
    }
}

/** Functions in this group only apply to instructions that map to
 * llvm::TerminatorInst instances.
 */
struct InstructionTerminatorValue {
    import llvm;

    LxInstructionTerminatorValue value;
    alias value this;

    auto asValue() {
        return Value(value);
    }

    UserValue asUser() {
        return UserValue(value.LxUserValue);
    }

    auto asInstr() {
        return InstructionValue(value);
    }

    /// Returns: range over the successor blocks.
    auto successors() {
        return SuccessorsRange(this);
    }

    /// Returns: the successor at the specified index
    BasicBlock successor(size_t idx) {
        assert(idx < LLVMGetNumSuccessors(value));
        return LLVMGetSuccessor(value, cast(uint) idx).LxBasicBlock.BasicBlock;
    }

    /** Update the specified successor to point at the provided block.
     *
     * @see llvm::TerminatorInst::setSuccessor
     */
    void setSuccessor(size_t idx, BasicBlock bb) {
        LLVMSetSuccessor(value, cast(uint) idx, bb);
    }

    /** Return if a branch is conditional.
     *
     * This only works on llvm::BranchInst instructions.
     *
     * @see llvm::BranchInst::isConditional
     */
    bool isConditional() {
        return LLVMIsConditional(this) != 0;
    }

    /** Return the condition of a branch instruction.
     *
     * This only works on llvm::BranchInst instructions.
     *
     * @see llvm::BranchInst::getCondition
     */
    Value condition() {
        assert(isConditional);
        return LLVMGetCondition(value).LxValue.Value;
    }

    /**
     * Set the condition of a branch instruction.
     *
     * This only works on llvm::BranchInst instructions.
     *
     * @see llvm::BranchInst::setCondition
     */
    //void LLVMSetCondition(LLVMValueRef Branch, LLVMValueRef Cond);

    /** Obtain the default destination basic block of a switch instruction.
     *
     * This only works on llvm::SwitchInst instructions.
     *
     * @see llvm::SwitchInst::getDefaultDest()
     */
    BasicBlock switchDefaultDest() {
        assert(asInstr.opcode == LxOpcode.Switch);
        return LLVMGetSwitchDefaultDest(value).LxBasicBlock.BasicBlock;
    }
}

/** Functions in this group only apply to instructions that map to
 * llvm::AllocaInst instances.
 */
struct InstructionAllocaValue {
    import llvm;
    import llvm_hiwrap.type.type;

    LxInstructionAllocaValue value;
    alias value this;

    auto asValue() {
        return Value(value);
    }

    auto asInstr() {
        return InstructionValue(value);
    }

    /// Obtain the type that is being allocated by the alloca instruction.
    Type type() {
        return LLVMGetAllocatedType(value).LxType.Type;
    }
}

/** Functions in this group only apply to instructions that map to
 * llvm::GetElementPtrInst instances.
 */
struct InstructionElementPtrValue {
    import llvm;

    LxInstructionElementPtrValue value;
    alias value this;

    auto asValue() {
        return Value(value);
    }

    auto asInstr() {
        return InstructionValue(value);
    }

    /** Check whether the given GEP instruction is inbounds.
     */
    bool isInBounds() {
        return LLVMIsInBounds(value) != 0;
    }

    /** Set the given GEP instruction to be inbounds or not.
     */
    void setInBounds(bool onoff) {
        LLVMSetIsInBounds(value, onoff ? 1 : 0);
    }
}

struct SuccessorsRange {
    import llvm;

    private size_t length_;
    private LxInstructionTerminatorValue value;

    this(InstructionTerminatorValue v) {
        value = v;
        length_ = LLVMGetNumSuccessors(v);
    }

    size_t length() {
        return length_;
    }

    BasicBlock opIndex(size_t index) {
        assert(index < length);
        return LLVMGetSuccessor(value, cast(uint) index).LxBasicBlock.BasicBlock;
    }

    import llvm_hiwrap.util;

    mixin IndexedRangeX!BasicBlock;
}
