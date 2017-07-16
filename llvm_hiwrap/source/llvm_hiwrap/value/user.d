/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.user;

import llvm_hiwrap.types;

/** Function in this group pertain to LLVMValueRef instances that descent from
 * llvm::User.
 *
 * This includes constants, instructions, and operators.
 *
 * TODO add a spelling function.
 */
struct UserValue {
    import llvm;
    import llvm_hiwrap.value.value;
    import llvm_hiwrap.value.use;

    LxUserValue value;
    alias value this;

    auto asValue() {
        return Value(this);
    }

    /// Returns: a range over all operands.
    OperandsRange operands() {
        return OperandsRange(this);
    }

    /**
     * Obtain an operand at a specific index in a llvm::User value.
     *
     * @see llvm::User::getOperand()
     */
    Operand operandAt(size_t index) {
        assert(index < countOperands);
        return LLVMGetOperand(this, cast(uint) index).LxValue.LxOperandValue.Operand;
    }

    /** Obtain the use of an operand at a specific index in a llvm::User value.
     *
     * @see llvm::User::getOperandUse()
     */
    UseValue operandUseAt(size_t index) {
        return LLVMGetOperandUse(this, cast(uint) index).LxUseValue.UseValue;
    }

    /** Set an operand at a specific index in a llvm::User value.
     *
     * @see llvm::User::setOperand()
     */
    void setOperandAt(size_t index, Value v) {
        LLVMSetOperand(this, cast(uint) index, v);
    }

    /** Obtain the number of operands in a llvm::User value.
     *
     * @see llvm::User::getNumOperands()
     */
    auto countOperands() {
        return LLVMGetNumOperands(this);
    }
}

struct Operand {
    import llvm;
    import llvm_hiwrap.value.value;
    import llvm_hiwrap.value.use;

    LxOperandValue value;
    alias value this;

    auto asValue() {
        return Value(this);
    }
}

struct OperandsRange {
    import llvm;
    import llvm_hiwrap.value.use;

    private immutable size_t length_;
    private UserValue value;

    this(UserValue v) {
        length_ = v.countOperands;
        value = v;
    }

    size_t length() {
        return length_;
    }

    Operand opIndex(size_t index) {
        return value.operandAt(index);
    }

    import llvm_hiwrap.util : IndexedRangeX;

    mixin IndexedRangeX!Operand;
}
