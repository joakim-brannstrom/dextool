/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

See: llvm-c/Core.h

 * Types have the following hierarchy:
 *
 *   types:
 *     integer type
 *     real type
 *     function type
 *     sequence types:
 *       array type
 *       pointer type
 *       vector type
 *     void type
 *     label type
 *     opaque type
*/
module llvm_hiwrap.type.type;

import llvm_hiwrap.types;

struct Type {
    import llvm : LLVMTypeRef, LLVMTypeKind, LLVMGetTypeKind;

    LxType type;
    alias type this;

    /** Obtain the enumerated type of a Type instance.
     *
     * See: llvm-c/Core.h
     */
    LxTypeKind kind() nothrow {
        auto r = LxTypeKind.Unknown;
        try {
            LLVMTypeKind tmp = LLVMGetTypeKind(rawPtr);
            if (tmp >= LxTypeKind.min && tmp <= LxTypeKind.max)
                r = cast(LxTypeKind) tmp;
        }
        catch (Exception e) {
        }

        return r;
    }

    bool isPrimitive() {
        import std.algorithm : among;

        with (LxTypeKind) {
            return kind.among(Void, Half, Float, Double, X86_FP80, FP128, PPC_FP128, Integer) != 0;
        }
    }

    bool isLabel() {
        return kind == LxTypeKind.Label;
    }

    bool isFunction() {
        return kind == LxTypeKind.Function;
    }

    bool isStruct() {
        return kind == LxTypeKind.Struct;
    }

    bool isArray() {
        return kind == LxTypeKind.Array;
    }

    bool isPointer() {
        return kind == LxTypeKind.Pointer;
    }

    bool isVector() {
        return kind == LxTypeKind.Vector;
    }

    bool isMetadata() {
        return kind == LxTypeKind.Metadata;
    }

    bool isToken() {
        return kind == LxTypeKind.Token;
    }

    bool isSequential() {
        import std.algorithm : among;

        with (LxTypeKind) {
            return kind.among(Array, Vector, Pointer) != 0;
        }
    }

    auto func() {
        assert(isFunction);
        import llvm_hiwrap.type.function_;

        return FunctionType(this);
    }

    auto struct_() {
        assert(isStruct);
        import llvm_hiwrap.type.struct_;

        return StructType(this);
    }

    // Note: exposing the specifics to make it easier to use correctly.
    // Some function are only valid to use for array types.
    LxArrayType array() {
        return LxArrayType(asSequential);
    }

    // Note: exposing the specifics to make it easier to use correctly.
    // Some function are only valid to use for array types.
    LxPointerType pointer() {
        return LxPointerType(asSequential);
    }

    // Note: exposing the specifics to make it easier to use correctly.
    // Some function are only valid to use for array types.
    LxVectorType vector() {
        return LxVectorType(asSequential);
    }

private:
    LxSequential asSequential() {
        import llvm : LLVMGetElementType;

        assert(isSequential);
        auto t = LLVMGetElementType(rawPtr);
        return LxSequential(LxType(t));
    }
}

/**
 * Sequential types represents "arrays" of types. This is a super class
 * for array, vector, and pointer types.
 *
 * All elements in a sequential type have the same type.
 */
struct LxSequentialImpl(LxTypeKind Kind) {
    import llvm;

    LxType type;
    alias type this;

    static if (Kind == LxTypeKind.Array) {
        /** Obtain the length of an array type.
         *
         * This only works on types that represent arrays.
         *
         * TODO I am unsure if the LLVM documentation mean sequential or array
         * when it states "only works for arrays".  Test what happens when the
         * type is a pointer or vector.
         */
        @property size_t length() {
            import std.traits : ReturnType;

            enum llvm_max_length = (ReturnType!LLVMGetArrayLength).max;
            static assert(llvm_max_length <= size_t.max,
                    "mismatch between LLVM API and the D length type");

            auto s = LLVMGetArrayLength(type);
            return s;
        }
    } else static if (Kind == LxTypeKind.Pointer) {
        /** Obtain the address space of a pointer type.
         *
         * This only works on types that represent pointers.
         */
        @property auto addressSpace() {
            return LLVMGetPointerAddressSpace(type);
        }
    } else static if (Kind == LxTypeKind.Vector) {
        /** Obtain the number of elements in a vector type.
         *
         * This only works on types that represent vectors.
         */
        @property size_t length() {
            import std.traits : ReturnType;

            enum llvm_max_length = (ReturnType!LLVMGetVectorSize).max;
            static assert(llvm_max_length <= size_t.max,
                    "mismatch between LLVM API and the D length type");

            auto s = LLVMGetVectorSize(type);
            return s;
        }
    }
}

alias LxSequential = LxSequentialImpl!(LxTypeKind.Unknown);
alias LxArrayType = LxSequentialImpl!(LxTypeKind.Array);
alias LxPointerType = LxSequentialImpl!(LxTypeKind.Pointer);
alias LxVectorType = LxSequentialImpl!(LxTypeKind.Vector);
