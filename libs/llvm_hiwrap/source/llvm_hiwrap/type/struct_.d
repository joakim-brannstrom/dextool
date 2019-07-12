/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.type.struct_;

import llvm_hiwrap.types;

struct StructType {
    import llvm;

    LxType type;
    alias type this;

    @property const(char)[] name() {
        import std.string : fromStringz;

        auto s = LLVMGetStructName(type);
        return s.fromStringz;
    }

    @property auto elements() {
        return ElementsRange(this);
    }

    /// Returns: Determine whether a structure is packed.
    bool isPacked() nothrow {
        return LLVMIsPackedStruct(type) != 0;
    }

    /// Returns: Determine whether a structure is opaque.
    bool isOpaque() nothrow {
        return LLVMIsOpaqueStruct(type) != 0;
    }
}

/// The elements defined in a struct.
struct ElementsRange {
    import llvm;

    StructType type;
    alias type this;

    // The number of elements in the struct.
    const size_t length;

    this(StructType t) nothrow {
        auto len = LLVMCountStructElementTypes(type);
        if (len >= size_t.max) {
            length = size_t.max;
            assert(0, "unreasonable parameter count (>= size_t)");
        } else {
            length = len;
        }
    }

    /// Returns: The type of the element at a given index in the structure.
    LxType opIndex(size_t index) nothrow {
        assert(index < length);
        assert(index < uint.max);

        auto t = LLVMStructGetTypeAtIndex(type, cast(uint) index);
        return LxType(t);
    }

    import llvm_hiwrap.util : IndexedRangeX;

    mixin IndexedRangeX!LxType;
}
