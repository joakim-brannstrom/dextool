/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains the simple type representation of llvm values and types.
It is meant to, when appropriate, reconstruct the llvm hierarchy in D.

The complex functions and other manipulation that are possible are found in the
.type and .value submodules.

The _simple_ types reflect the hierarchy. They are prefixed with Lx.
The comlex types add operations. This allows compositions of operations.
*/
module llvm_hiwrap.types;

import llvm;

/// LLVM-4.0
/// See: llvm-c/Core.h
enum LxValueKind {
    Argument,
    BasicBlock,
    MemoryUse,
    MemoryDef,
    MemoryPhi,

    Function,
    GlobalAlias,
    GlobalIFunc,
    GlobalVariable,
    BlockAddress,
    ConstantExpr,
    ConstantArray,
    ConstantStruct,
    ConstantVector,

    UndefValue,
    ConstantAggregateZero,
    ConstantDataArray,
    ConstantDataVector,
    ConstantInt,
    ConstantFP,
    ConstantPointerNull,
    ConstantTokenNone,

    MetadataAsValue,
    InlineAsm,

    Instruction,

    Unknown
}

/// LLVM-4.0
/// See: llvm-c/Analysis.h
enum LxVerifierFailureAction {
    /// verifier will print to stderr and abort()
    AbortProcessAction,
    /// verifier will print to stderr and return 1
    PrintMessageAction,
    /// verifier will just return 1
    ReturnStatusAction
}

/// LLVM-4.0
/// See: llvm-c/Core.h
enum LxDiagnosticSeverity {
    Error,
    Warning,
    Remark,
    Note
}

/// LLVM-4.0
/// See: llvm-c/Core.h
enum LxTypeKind {
    Void, /// type with no size
    Half, /// 16 bit floating point type
    Float, /// 32 bit floating point type
    Double, /// 64 bit floating point type
    X86_FP80, /// 80 bit floating point type (X87)
    FP128, /// 128 bit floating point type (112-bit mantissa)
    PPC_FP128, /// 128 bit floating point type (two 64-bits)
    Label, /// Labels
    Integer, /// Arbitrary bit width integers
    Function, /// Functions
    Struct, /// Structures
    Array, /// Arrays
    Pointer, /// Pointers
    Vector, /// SIMD 'packed' format, or other vector type
    Metadata, /// Metadata
    X86_MMX, /// X86 MMX
    Token, /// Tokens

    /* Added by llvm_hiwrap.
     * Decouples the users of LxTypeKind from LLVMTypeKind.
     *
     * By having an unknown type the enum in the official LLVM lib can be
     * extended without breaking the use of this enum.
     * Lessons learned from libclang is that the enums will be extended.
     */
    Unknown,
}

/// LLVM-4.0
/// See: llvm-c/Core.h
enum LxOpcode {
    /* Terminator Instructions */
    Ret = 1,
    Br = 2,
    Switch = 3,
    IndirectBr = 4,
    Invoke = 5,
    /* removed 6 due to API changes */
    Unreachable = 7,

    /* Standard Binary Operators */
    Add = 8,
    FAdd = 9,
    Sub = 10,
    FSub = 11,
    Mul = 12,
    FMul = 13,
    UDiv = 14,
    SDiv = 15,
    FDiv = 16,
    URem = 17,
    SRem = 18,
    FRem = 19,

    /* Logical Operators */
    Shl = 20,
    LShr = 21,
    AShr = 22,
    And = 23,
    Or = 24,
    Xor = 25,

    /* Memory Operators */
    Alloca = 26,
    Load = 27,
    Store = 28,
    GetElementPtr = 29,

    /* Cast Operators */
    Trunc = 30,
    ZExt = 31,
    SExt = 32,
    FPToUI = 33,
    FPToSI = 34,
    UIToFP = 35,
    SIToFP = 36,
    FPTrunc = 37,
    FPExt = 38,
    PtrToInt = 39,
    IntToPtr = 40,
    BitCast = 41,
    AddrSpaceCast = 60,

    /* Other Operators */
    ICmp = 42,
    FCmp = 43,
    PHI = 44,
    Call = 45,
    Select = 46,
    UserOp1 = 47,
    UserOp2 = 48,
    VAArg = 49,
    ExtractElement = 50,
    InsertElement = 51,
    ShuffleVector = 52,
    ExtractValue = 53,
    InsertValue = 54,

    /* Atomic operators */
    Fence = 55,
    AtomicCmpXchg = 56,
    AtomicRMW = 57,

    /* Exception Handling Operators */
    Resume = 58,
    LandingPad = 59,
    CleanupRet = 61,
    CatchRet = 62,
    CatchPad = 63,
    CleanupPad = 64,
    CatchSwitch = 65,

    /// Added by llvm_hiwrap.
    Unknown,
}

/// LLVM-4.0
/// See: llvm-c/Core.h
enum LxIntPredicate {
    EQ = 32, /**< equal */
    NE, /**< not equal */
    UGT, /**< unsigned greater than */
    UGE, /**< unsigned greater or equal */
    ULT, /**< unsigned less than */
    ULE, /**< unsigned less or equal */
    SGT, /**< signed greater than */
    SGE, /**< signed greater or equal */
    SLT, /**< signed less than */
    SLE /**< signed less or equal */
}

/// LLVM-4.0
/// See: llvm-c/Core.h
enum LxRealPredicate {
    PredicateFalse, /**< Always false (always folded) */
    OEQ, /**< True if ordered and equal */
    OGT, /**< True if ordered and greater than */
    OGE, /**< True if ordered and greater than or equal */
    OLT, /**< True if ordered and less than */
    OLE, /**< True if ordered and less than or equal */
    ONE, /**< True if ordered and operands are unequal */
    ORD, /**< True if ordered (no nans) */
    UNO, /**< True if unordered: isnan(X) | isnan(Y) */
    UEQ, /**< True if unordered or equal */
    UGT, /**< True if unordered or greater than */
    UGE, /**< True if unordered, greater than, or equal */
    ULT, /**< True if unordered or less than */
    ULE, /**< True if unordered, less than, or equal */
    UNE, /**< True if unordered or not equal */
    PredicateTrue /**< Always true (always folded) */
}

/// LLVM-4.0
/// See: llvm-c/Core.h
enum LxCallConv {
    C,
    Fast,
    Cold,
    WebKitJS,
    AnyReg,
    X86Stdcall,
    X86Fastcall,

    /// Added by llvm_hiwrap.
    Unknown
}

/// Convert a llvm.LLVMCallConv.
LxCallConv toCallConv(LLVMCallConv v) {
    switch (v) {
    case 0:
        return LxCallConv.C;
    case 8:
        return LxCallConv.Fast;
    case 9:
        return LxCallConv.Cold;
    case 12:
        return LxCallConv.WebKitJS;
    case 13:
        return LxCallConv.AnyReg;
    case 64:
        return LxCallConv.X86Stdcall;
    case 65:
        return LxCallConv.X86Fastcall;
    default:
        return LxCallConv.Unknown;
    }
}

/// ptr to a null terminated array of null terminated C strings.
struct LxMessage {
    char* rawPtr;
    private char[] str;

    alias rawPtr this;

    @disable this(this);

    ~this() {
        import llvm : LLVMDisposeMessage;

        LLVMDisposeMessage(rawPtr);
    }

    const(char)[] toChar() {
        if (str.length == 0) {
            import std.string : fromStringz;

            str = rawPtr.fromStringz;
        }
        return str;
    }
}

struct LxAttribute {
    import llvm : LLVMAttributeRef;

    LLVMAttributeRef rawPtr;
    alias rawPtr this;

    this(LLVMAttributeRef v) {
        rawPtr = v;
    }
}

struct LxBasicBlock {
    import llvm : LLVMBasicBlockRef;

    LLVMBasicBlockRef rawPtr;
    alias rawPtr this;

    this(LLVMBasicBlockRef v) {
        rawPtr = v;
    }
}

/// The entry block in a function.
struct LxEntryBasicBlock {
    LxBasicBlock value;
    alias value this;
}

/** Represents an individual value in LLVM IR.
 *
 * See: llvm-c/Types.h
 */
struct LxValue {
    import llvm : LLVMValueRef;

    LLVMValueRef rawPtr;
    alias rawPtr this;

    this(LLVMValueRef v) @safe pure nothrow @nogc {
        rawPtr = v;
    }
}

/// Unnamed node
struct LxMetadataNodeValue {
    LxValue value;
    alias value this;
}

struct LxMetadataStringValue {
    LxValue value;
    alias value this;
}

struct LxNamedMetadataNodeValue {
    LxValue value;
    alias value this;
}

// TODO should it also carry the name as a string?
// I do NOT want these nodes to be heavy so not added yet.
struct LxNamedMetadataValue {
    LxNamedMetadataNodeValue[] operands;
    alias operands this;
}

struct LxResolvedNamedMetadataValue {
    LxMetadataNodeValue operands;
    alias operands this;
}

struct LxInstructionValue {
    LxValue value;
    alias value this;
}

struct LxInstructionCallValue {
    LxInstructionValue value;
    alias value this;
}

struct LxInstructionTerminatorValue {
    LxInstructionValue value;
    alias value this;
}

struct LxInstructionAllocaValue {
    LxInstructionValue value;
    alias value this;
}

struct LxInstructionElementPtrValue {
    LxInstructionValue value;
    alias value this;
}

struct LxType {
    import llvm : LLVMTypeRef;

    LLVMTypeRef rawPtr;
    alias rawPtr this;

    this(LLVMTypeRef v) @safe @nogc nothrow {
        rawPtr = v;
    }
}

struct LxConstantValue {
    LxUserValue value;
    alias value this;
}

struct LxFunctionValue {
    LxUserValue value;
    alias value this;
}

struct LxGlobalValue {
}

struct LxGlobalAliasValue {
}

struct LxScalarConstantValue {
}

struct LxCompositeConstantValue {
}

struct LxConstantGlobalValue {
}

/**
 * Each LLVMUseRef (which corresponds to a llvm::Use instance) holds a
 * llvm::User and llvm::Value.
 */
struct LxUseValue {
    LLVMUseRef rawPtr;
    alias rawPtr this;
}

struct LxUserValue {
    LxValue value;
    alias value this;
}

struct LxOperandValue {
    LxValue value;
    alias value this;
}
