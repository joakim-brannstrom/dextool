/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.use;

import llvm_hiwrap.types;
import llvm_hiwrap.value.user;

/** This module defines functions that allow you to inspect the uses of a
 * LLVMValueRef.
 *
 * It is possible to obtain an LLVMUseRef for any LLVMValueRef instance. Each
 * LLVMUseRef (which corresponds to a llvm::Use instance) holds a llvm::User
 * and llvm::Value.
 */
struct UseValue {
    import llvm;
    import llvm_hiwrap.value.user;
    import llvm_hiwrap.value.value;

    LxUseValue value;
    alias value this;

    /** Obtain the user value for a user.
     *
     * The returned value corresponds to a llvm::User type.
     *
     * @see llvm::Use::getUser()
     */
    UserValue user() {
        return LLVMGetUser(this).LxValue.LxUserValue.UserValue;
    }

    /** Obtain the value this use corresponds to.
     *
     * @see llvm::Use::get().
     */
    Value usedValue() {
        return LLVMGetUsedValue(this).LxValue.Value;
    }
}
