/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

From the LLVM source code, llvm/IR/BasicBlock.h

# LLVM Basic Block Representation

This represents a single basic block in LLVM. A basic block is simply a
container of instructions that execute sequentially. Basic blocks are Values
because they are referenced by instructions such as branches and switch tables.
The type of a BasicBlock is "Type::LabelTy" because the basic block represents
a label to which a branch can jump.

A well formed basic block is formed of a list of non-terminating instructions
followed by a single TerminatorInst instruction.  TerminatorInst's may not
occur in the middle of basic blocks, and must terminate the blocks. The
BasicBlock class allows malformed basic blocks to occur because it may be
useful in the intermediate stage of constructing or modifying a program.
However, the verifier will ensure that basic blocks are "well formed".
*/
module llvm_hiwrap.value.basic_block;

import std.typecons : Nullable;

import llvm_hiwrap.types;
import llvm_hiwrap.value.function_;
import llvm_hiwrap.value.value;

/// Note that isTerminator and isCall overlap.
bool isTerminator(LxOpcode op) {
    switch (op) with (LxOpcode) {
    case Ret:
        goto case;
    case Br:
        goto case;
    case Switch:
        goto case;
    case IndirectBr:
        goto case;
    case Invoke:
        return true;
    default:
        return false;
    }
}

bool isAlloca(LxOpcode op) {
    return op == LxOpcode.Alloca;
}

bool isElementPtr(LxOpcode op) {
    return op == LxOpcode.GetElementPtr;
}

bool isCall(LxOpcode op) {
    switch (op) with (LxOpcode) {
    case Invoke:
        goto case;
    case Call:
        return true;
    default:
        return false;
    }
}

/** A basic block represents a single entry single exit section of code.
 *
 * Basic blocks contain a list of instructions which form the body of
 * the block.
 *
 * Basic blocks belong to functions. They have the type of label.
 *
 * Basic blocks are themselves values. However, the C API models them as
 * LLVMBasicBlockRef.
 *
 * See: llvm::BasicBlock
 */
struct BasicBlock {
    import llvm;
    import llvm_hiwrap.value.instruction;

    LxBasicBlock lx;
    alias lx this;

    /// Uses the pointer as a unique identifier.
    size_t id() {
        return cast(size_t) lx;
    }

    /// Convert a basic block instance to a value type.
    Value asValue() {
        auto v = LLVMBasicBlockAsValue(lx);
        return LxValue(v).Value;
    }

    /**
     * Obtain the string name of a basic block.
     */
    @property const(char)[] name() {
        import std.string : fromStringz;
        import llvm : LLVMGetBasicBlockName;

        auto s = LLVMGetBasicBlockName(lx);
        return s.fromStringz;
    }

    /** Obtain the function to which a basic block belongs.
     *
     * See: llvm::BasicBlock::getParent()
     *
     * TODO assuming that the base type is always a function.
     */
    FunctionValue parent() {
        auto raw = LLVMGetBasicBlockParent(lx);
        return raw.LxValue.LxUserValue.LxFunctionValue.FunctionValue;
    }

    /// A range over the instructions in the block
    InstructionRange instructions() {
        return InstructionRange(this);
    }

    /**
     * Obtain the terminator instruction for a basic block.
     *
     * If the basic block does not have a terminator (it is not well-formed
     * if it doesn't), then NULL is returned.
     *
     * The returned LLVMValueRef corresponds to a llvm::TerminatorInst.
     *
     * @see llvm::BasicBlock::getTerminator()
     */
    Nullable!InstructionTerminatorValue terminator() {
        auto raw = LLVMGetBasicBlockTerminator(lx);
        return typeof(return)(
                raw.LxValue.LxInstructionValue.LxInstructionTerminatorValue
                .InstructionTerminatorValue);
    }

    /**
     * Move a basic block to before another one.
     *
     * @see llvm::BasicBlock::moveBefore()
     */
    //void LLVMMoveBasicBlockBefore(LLVMBasicBlockRef BB, LLVMBasicBlockRef MovePos);

    /**
     * Move a basic block to after another one.
     *
     * @see llvm::BasicBlock::moveAfter()
     */
    //void LLVMMoveBasicBlockAfter(LLVMBasicBlockRef BB, LLVMBasicBlockRef MovePos);

    /** Obtain the first instruction in a basic block.
     *
     * The returned LLVMValueRef corresponds to a llvm::Instruction
     * instance.
     */
    InstructionValue firstInstr() {
        return LLVMGetFirstInstruction(this).LxValue.LxInstructionValue.InstructionValue;
    }

    /** Obtain the last instruction in a basic block.
     *
     * The returned LLVMValueRef corresponds to an LLVM:Instruction.
     *
     * TODO I assume this is the last instruction and not _end_.
     */
    InstructionValue lastInstr() {
        return LLVMGetLastInstruction(this).LxValue.LxInstructionValue.InstructionValue;
    }

    /**
     * Remove a basic block from a function and delete it.
     *
     * This deletes the basic block from its containing function and deletes
     * the basic block itself.
     *
     * @see llvm::BasicBlock::eraseFromParent()
     */
    //void LLVMDeleteBasicBlock(LLVMBasicBlockRef BB);

    /**
     * Remove a basic block from a function.
     *
     * This deletes the basic block from its containing function but keep
     * the basic block alive.
     *
     * @see llvm::BasicBlock::removeFromParent()
     */
    //void LLVMRemoveBasicBlockFromParent(LLVMBasicBlockRef BB);
}

struct EntryBasicBlock {
    import llvm;
    import llvm_hiwrap.value.instruction;

    LxEntryBasicBlock lx;
    alias lx this;

    BasicBlock asBasicBlock() {
        return lx.BasicBlock;
    }
}

struct InstructionRange {
    import std.typecons : Nullable;
    import llvm_hiwrap.value.instruction;

    private Nullable!InstructionValue cur;

    this(BasicBlock bb) {
        cur = bb.firstInstr;
    }

    InstructionValue front() {
        assert(!empty, "Can't get front of an empty range");
        return cur.get;
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");
        cur = cur.get.nextInstr;
    }

    bool empty() {
        return cur.isNull;
    }
}

mixin template BasicBlockAccept(VisitorT, UserT) {
    import llvm_hiwrap.value.basic_block;

    void implAccept(ref EntryBasicBlock entry) {
        import llvm_hiwrap.ast.tree : maybeCallVisit;

        {
            auto bb = entry.asBasicBlock;
            implAcceptInstructions(bb);
        }

        auto term = entry.asBasicBlock.terminator;
        if (term.isNull) {
            return;
        }

        foreach (b; term.get.successors) {
            maybeCallVisit(this, user, b);
        }
    }

    void implAccept(ref BasicBlock n) {
        import llvm_hiwrap.ast.tree : maybeCallVisit;

        implAcceptInstructions(n);

        auto term = n.terminator;
        if (term.isNull) {
            return;
        }

        foreach (b; term.get.successors) {
            maybeCallVisit(this, user, b);
        }
    }

    private void implAcceptInstructions(ref BasicBlock n) {
        import llvm_hiwrap.ast.tree : maybeCallVisit;
        import llvm_hiwrap.value.instruction;
        import llvm_hiwrap.types;

        static void fallback(T)(ref VisitorT!UserT self, ref UserT user, ref T node) {
            auto n = node.value.LxInstructionValue.InstructionValue;
            maybeCallVisit(self, user, n);
        }

        foreach (instr; n.instructions) {
            if (instr.opcode.isAlloca) {
                auto nn = instr.LxInstructionAllocaValue.InstructionAllocaValue;
                maybeCallVisit(this, user, nn, &fallback!InstructionAllocaValue);
            } else if (instr.opcode.isCall) {
                auto nn = instr.LxInstructionCallValue.InstructionCallValue;
                maybeCallVisit(this, user, nn, &fallback!InstructionCallValue);
            } else if (instr.opcode.isElementPtr) {
                auto nn = instr.LxInstructionElementPtrValue.InstructionElementPtrValue;
                maybeCallVisit(this, user, nn, &fallback!InstructionElementPtrValue);
            } else if (instr.opcode.isTerminator) {
                auto nn = instr.LxInstructionTerminatorValue.InstructionTerminatorValue;
                maybeCallVisit(this, user, nn, &fallback!InstructionTerminatorValue);
            } else {
                maybeCallVisit(this, user, instr);
            }
        }
    }
}

/** A depth-first visitor.
 *
 * See: llvm_hiwrap.ast.tree
 *
 * Accepted node types are:
 *  - InstructionValue
 *  - InstructionCallValue
 *  - InstructionTerminatorValue
 *  - InstructionAllocaValue
 *  - InstructionElementPtrValue
 */
struct BasicBlockVisitor(UserT) {
    UserT user;

    void visit(ref BasicBlock n) {
        import llvm_hiwrap.ast.tree;

        static void fallback(T)(ref this self, ref UserT user, ref T node) {
            accept(n, self);
        }

        maybeCallVisit(this, user, n);
    }

    mixin BasicBlockAccept!(BasicBlockVisitor, UserT);
}

@("shall be an instance of BasicBlockVisitor")
unittest {
    import llvm_hiwrap.ast.tree;

    struct Null {
    }

    BasicBlockVisitor!Null v;
}
