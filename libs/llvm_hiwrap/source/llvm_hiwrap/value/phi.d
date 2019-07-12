/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.phi;

import llvm_hiwrap.types;

/** Functions in this group only apply to instructions that map to
 * llvm::PHINode instances.
 *
 * PHINode is a subgroup of Instruction.
 */
struct PhiValue {
    LxInstructionValue value;
    alias value this;

    /**
     * Add an incoming value to the end of a PHI list.
     */
    //void LLVMAddIncoming(LLVMValueRef PhiNode, LLVMValueRef *IncomingValues,
    //                     LLVMBasicBlockRef *IncomingBlocks, unsigned Count);

    /// Obtain the number of incoming basic blocks to a PHI node.
    IncomingBlocksRange incomingBlocks() {
        return IncomingBlocksRange(this);
    }
}

/// The incoming value can be represenented as either a Value or BasicBlock.
struct IncomingPair {
    import llvm_hiwrap.value.basic_block;

    BasicBlock block;
    LxValue value;
}

struct IncomingBlocksRange {
    import llvm;
    import llvm_hiwrap.value.basic_block;

    private PhiValue phi;

    const size_t length;

    this(PhiValue v) {
        phi = v;
        length = LLVMCountIncoming(v);
    }

    private auto makePair(size_t index) {
        // Obtain an incoming value to a PHI node as an LLVMValueRef.
        auto llvm_value = LLVMGetIncomingValue(phi, cast(uint) index);
        // Obtain an incoming value to a PHI node as an LLVMBasicBlockRef.
        auto llvm_bb = LLVMGetIncomingBlock(phi, cast(uint) index);
        return IncomingPair(llvm_bb.LxBasicBlock.BasicBlock, llvm_value.LxValue);
    }

    IncomingPair opIndex(size_t index) {
        assert(index < length);
        return makePair(index);
    }

    import llvm_hiwrap.util;

    mixin IndexedRangeX!IncomingPair;
}
