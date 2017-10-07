/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.metadata;

import llvm_hiwrap.types;
import llvm_hiwrap.value.value;

/** Example of a named metadata node: !foo = !{!4, !3}
 *
 * See Context for how to convert this to a MetadataNodeValue.
 */
struct NamedMetadataValue {
    LxNamedMetadataValue value;
    alias value this;
}

/** Correspond to a named metadata node where the operands are resolved.
 *
 * An example would be in pseudo LLVM IR:
 * !0 = !{i32 4}
 * !1 = !{i32 10}
 * !foo = !{!0, !1}
 *
 * resolved to:
 * !<anonymouse> = !{!{i32 4}, !{i32 10}}
 *
 * Note how it wrappes the data. But it is not _true_ data but still only
 * references. But one reference, the MDNode, have at least been stripped away.
 *
 * This lead to the simple retrival of data via LLVMGetMDNodeOperands.
 */
struct ResolvedNamedMetadataValue {
    import llvm;
    import llvm_hiwrap.context : Context;

    LxResolvedNamedMetadataValue value;
    alias value this;

    /// Obtain the number of operands.
    auto countOperands() {
        return LLVMGetMDNodeNumOperands(this);
    }

    /// Obtain the given MDNode's operands.
    OperandsValue2 operands() {
        return OperandsValue2(this);
    }
}

/**
 * It is statically known that the operands are all MDNode's wrapping values
 * because this is derived from a named metadata.
 *
 * See Core.cpp function LLVMMDStringInContext in the llvm source code.
 */
struct OperandsValue2 {
    import llvm;
    import llvm_hiwrap.value.value;

    private LLVMValueRef[] ops;
    private const size_t length_;

    this(ResolvedNamedMetadataValue v) {
        length_ = v.countOperands;
        if (length_ != 0) {
            ops.length = length_;
            LLVMGetMDNodeOperands(v, ops.ptr);
        }
    }

    size_t length() {
        return length_;
    }

    MetadataNodeValue opIndex(size_t index) {
        return ops[index].LxValue.LxMetadataNodeValue.MetadataNodeValue;
    }

    import llvm_hiwrap.util : IndexedRangeX;

    mixin IndexedRangeX!MetadataNodeValue;
}

/** Correspond to an unnamed metadata node.
 *
 * Example of a node: !0 = !{!"test\00", i32 10}
 *
 * For the composite nodes (DICompositeType) types.
 * See: https://llvm.org/docs/LangRef.html#metadata
 */
struct MetadataNodeValue {
    import llvm;
    import llvm_hiwrap.context : Context;

    LxMetadataNodeValue value;
    alias value this;

    /// Obtain the number of operands.
    auto countOperands() {
        return LLVMGetMDNodeNumOperands(this);
    }

    /// Obtain the given MDNode's operands.
    OperandsValue operands() {
        return OperandsValue(this);
    }
}

struct OperandsValue {
    import llvm;
    import llvm_hiwrap.value.value;

    private LLVMValueRef[] ops;
    private const size_t length_;

    this(MetadataNodeValue v) {
        length_ = v.countOperands;
        if (length_ != 0) {
            ops.length = length_;
            LLVMGetMDNodeOperands(v, ops.ptr);
        }
    }

    size_t length() {
        return length_;
    }

    Value opIndex(size_t index) {
        return ops[index].LxValue.Value;
    }

    import llvm_hiwrap.util : IndexedRangeX;

    mixin IndexedRangeX!Value;
}

/// Obtained from a Context.
struct MetadataStringValue {
    import llvm;

    LxMetadataStringValue value;
    alias value this;

    /** Obtain the underlying string from a MDString value.
     *
     * @param V Instance to obtain string from.
     * @param Length Memory address which will hold length of returned string.
     * @return String data in MDString.
     */
    const(char)[] toString() {
        uint len;
        auto s = LLVMGetMDString(this, &len);
        return s[0 .. len];
    }
}

/** Obtain a MDString value from the global context.
 */
//LLVMValueRef LLVMMDNode(LLVMValueRef *Vals, unsigned Count);
