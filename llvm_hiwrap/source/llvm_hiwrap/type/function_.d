/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.type.function_;

import llvm_hiwrap.types;

struct FunctionType {
    LxType type;
    alias type this;

    /// Returns: whether a function type is variadic.
    bool isVariadic() nothrow {
        import llvm : LLVMIsFunctionVarArg;

        return LLVMIsFunctionVarArg(type) != 0;
    }

    /// Returns: Obtain the Type this function Type returns.
    LxType returnType() nothrow {
        import llvm : LLVMGetReturnType;

        auto t = LLVMGetReturnType(type);
        return LxType(t);
    }

    /// Returns: an iterator over the parameters.
    ParametersRange parameters() nothrow {
        return ParametersRange(this);
    }
}

/// The parameters for a function.
struct ParametersRange {
    import llvm;

    FunctionType type;
    alias type this;

    private LLVMTypeRef[] params;

    /// The number of parameters this function accepts.
    const size_t length;

    this(FunctionType t) nothrow {
        import llvm : LLVMCountParamTypes;

        auto len = LLVMCountParamTypes(type);
        if (len >= size_t.max) {
            length = size_t.max;
            assert(0, "unreasonable parameter count (>= size_t)");
        } else {
            length = len;
        }

        params.length = length;
        LLVMGetParamTypes(type, params.ptr);
    }

    LxType opIndex(size_t index) @safe nothrow @nogc {
        assert(index < length);
        return LxType(params[index]);
    }

    import llvm_hiwrap.util : IndexedRangeX;

    mixin IndexedRangeX!LxType;
}
