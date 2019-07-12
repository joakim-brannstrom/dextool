/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.analysis;

import llvm_hiwrap.types : LxValue;

/** Open up a ghostview window that displays the CFG of the current function.
 *
 * Useful for debugging.
 */
void viewCFG(LxValue v) {
    import llvm : LLVMViewFunctionCFG;

    LLVMViewFunctionCFG(v);
}
