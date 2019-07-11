/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.parameter;

import llvm_hiwrap.types;

/** Functions in this group relate to arguments/parameters on functions.
 *
 * Functions in this group expect LLVMValueRef instances that correspond
 * to llvm::Function instances.
 */
struct ParameterValue {
    import llvm;
    import llvm_hiwrap.value.function_ : FunctionValue;

    LxValue value;
    alias value this;

    /** Obtain the function to which this argument belongs.
     *
     * Unlike other functions in this group, this one takes an LLVMValueRef
     * that corresponds to a llvm::Attribute.
     *
     * The returned LLVMValueRef is the llvm::Function to which this
     * argument belongs.
     *
     * TODO what does it mean by an Attribute? I don't think this will work.
     */
    FunctionValue parent() {
        return LLVMGetParamParent(value).LxValue.LxUserValue.LxFunctionValue.FunctionValue;
    }

    /**
     * Set the alignment for a function parameter.
     *
     * @see llvm::Argument::addAttr()
     * @see llvm::AttrBuilder::addAlignmentAttr()
     */
    //void LLVMSetParamAlignment(LLVMValueRef Arg, unsigned Align);
}
